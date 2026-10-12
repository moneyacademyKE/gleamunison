//// Minimal LSP server: diagnostics over stdio, Content-Length framed.
//// One function per verb, all pure: JSON body in, list of reply bodies out.
//// The stdio pump (cli_lsp) is the only impure part.

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleamunison/ast
import gleamunison/elab_types
import gleamunison/elaborate as elab
import gleamunison/json
import gleamunison/lexer
import gleamunison/repl_eval
import gleamunison/type_pretty
import gleamunison/types.{empty_cache}
import gleamunison/verify

/// One diagnostic: LSP wants 0-based positions; our spans are 1-based.
pub type Diagnostic {
  Diagnostic(line: Int, col: Int, message: String)
}

/// Split one Content-Length framed message off a buffer. Error means
/// incomplete: the pump keeps reading and retries.
pub fn decode_framed(buffer: String) -> Result(#(String, String), Nil) {
  case string.split_once(buffer, "\r\n\r\n") {
    Error(_) -> Error(Nil)
    Ok(#(headers, rest)) -> {
      use length <- result.try(content_length(headers))
      case string.length(rest) >= length {
        False -> Error(Nil)
        True -> {
          let body = string.slice(rest, 0, length)
          let remaining = string.drop_start(rest, length)
          Ok(#(body, remaining))
        }
      }
    }
  }
}

fn content_length(headers: String) -> Result(Int, Nil) {
  let lines = string.split(headers, "\r\n")
  let found =
    list.find_map(lines, fn(line) {
      case string.split_once(line, ":") {
        Ok(#(name, value)) ->
          case string.lowercase(string.trim(name)) == "content-length" {
            True -> int.parse(string.trim(value))
            False -> Error(Nil)
          }
        Error(_) -> Error(Nil)
      }
    })
  found
}

pub fn encode_frame(body: String) -> String {
  "Content-Length: " <> int.to_string(string.length(body)) <> "\r\n\r\n" <> body
}

/// Handle one JSON-RPC body. Returns reply bodies (responses and
/// notifications) to frame and write, plus the new server state.
pub fn handle_message(body: String, state: State) -> #(List(String), State) {
  case json.decode(bit_array.from_string(body)) {
    Error(_) -> #([], state)
    Ok(dyn) ->
      case decode.run(dyn, message_decoder()) {
        Error(_) -> #([], state)
        Ok(msg) -> dispatch(msg, state)
      }
  }
}

/// Server state: the open documents. Stateless services can't answer
/// "what is THIS symbol in THIS file" — hover/definition/completion read
/// the document the client opened.
pub type State {
  State(docs: dict.Dict(String, String))
}

pub fn new_state() -> State {
  State(docs: dict.new())
}

pub fn open_doc(state: State, uri: String, text: String) -> State {
  State(docs: dict.insert(state.docs, uri, text))
}

type Message {
  Message(id: Option(Dynamic), method: String, params: Dict(String, Dynamic))
}

fn message_decoder() -> decode.Decoder(Message) {
  use method <- decode.field("method", decode.string)
  use id <- decode.optional_field("id", None, decode.map(decode.dynamic, Some))
  // params may be missing OR null (shutdown sends null) — both mean none.
  use params <- decode.optional_field(
    "params",
    dict.new(),
    decode.one_of(decode.dict(decode.string, decode.dynamic), or: [
      decode.success(dict.new()),
    ]),
  )
  decode.success(Message(id:, method:, params:))
}

fn dispatch(msg: Message, state: State) -> #(List(String), State) {
  case msg.method {
    "initialize" ->
      case msg.id {
        Some(id) -> #([respond(id, initialize_result())], state)
        None -> #([], state)
      }
    "initialized" -> #([], state)
    "shutdown" ->
      case msg.id {
        Some(id) -> #([respond(id, "null")], state)
        None -> #([], state)
      }
    "exit" -> #([], state)
    "textDocument/didOpen" ->
      case extract_doc(msg.params, from_open) {
        Error(_) -> #(["{}"], state)
        Ok(doc) -> #(
          [publish(doc.uri, diagnose(doc.text))],
          open_doc(state, doc.uri, doc.text),
        )
      }
    "textDocument/didChange" ->
      case extract_doc(msg.params, from_change) {
        Error(_) -> #(["{}"], state)
        Ok(doc) -> #(
          [publish(doc.uri, diagnose(doc.text))],
          open_doc(state, doc.uri, doc.text),
        )
      }
    "textDocument/hover" -> #(hover_reply(msg, state), state)
    "textDocument/definition" -> #(definition_reply(msg, state), state)
    "textDocument/completion" -> #(completion_reply(msg, state), state)
    _ ->
      case msg.id {
        Some(id) -> #([error_response(id, -32_601, "Method not found")], state)
        None -> #([], state)
      }
  }
}

fn initialize_result() -> String {
  "{\"capabilities\":{\"textDocumentSync\":1,\"hoverProvider\":true,"
  <> "\"definitionProvider\":true,\"completionProvider\":{\"triggerCharacters\":[]}},"
  <> "\"serverInfo\":{\"name\":\"gleamunison\",\"version\":\"3.16.0\"}}"
}

fn respond(id: Dynamic, result: String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":"
  <> id_json(id)
  <> ",\"result\":"
  <> result
  <> "}"
}

fn error_response(id: Dynamic, code: Int, message: String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":"
  <> id_json(id)
  <> ",\"error\":{\"code\":"
  <> int.to_string(code)
  <> ",\"message\":"
  <> jstr(message)
  <> "}}"
}

fn id_json(id: Dynamic) -> String {
  case decode.run(id, decode.int) {
    Ok(n) -> int.to_string(n)
    Error(_) ->
      case decode.run(id, decode.string) {
        Ok(s) -> jstr(s)
        Error(_) -> "null"
      }
  }
}

// ── Diagnostics ─────────────────────────────────────────────────────────────

type DocSource {
  DocSource(uri: String, text: String)
}

const from_open = True

const from_change = False

fn extract_doc(
  params: Dict(String, Dynamic),
  is_open: Bool,
) -> Result(DocSource, Nil) {
  use doc_dyn <- result.try(dict.get(params, "textDocument"))
  let doc_decoder = {
    use uri <- decode.field("uri", decode.string)
    decode.success(uri)
  }
  use uri <- result.try(case decode.run(doc_dyn, doc_decoder) {
    Ok(u) -> Ok(u)
    Error(_) -> Error(Nil)
  })
  use text <- result.try(case is_open {
    True -> {
      let text_decoder = {
        use t <- decode.field("text", decode.string)
        decode.success(t)
      }
      case decode.run(doc_dyn, text_decoder) {
        Ok(t) -> Ok(t)
        Error(_) -> Error(Nil)
      }
    }
    False -> {
      use changes <- result.try(dict.get(params, "contentChanges"))
      let change_decoder =
        decode.list({
          use t <- decode.field("text", decode.string)
          decode.success(t)
        })
      case decode.run(changes, change_decoder) {
        Ok([first, ..]) -> Ok(first)
        _ -> Error(Nil)
      }
    }
  })
  Ok(DocSource(uri:, text:))
}

fn publish(uri: String, diagnostics: List(Diagnostic)) -> String {
  let diags =
    list.map(diagnostics, fn(d) {
      "{\"range\":{\"start\":{\"line\":"
      <> int.to_string(d.line)
      <> ",\"character\":"
      <> int.to_string(d.col)
      <> "},\"end\":{\"line\":"
      <> int.to_string(d.line)
      <> ",\"character\":"
      <> int.to_string(d.col + 1)
      <> "}},\"severity\":1,\"message\":"
      <> jstr(d.message)
      <> "}"
    })
  "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\","
  <> "\"params\":{\"uri\":"
  <> jstr(uri)
  <> ",\"diagnostics\":["
  <> string.join(diags, ",")
  <> "]}}"
}

/// Parse + elaborate source text, returning one diagnostic per error.
/// Pure: no compilation, no loading, no handlers. Spans come through as
/// 1-based from elaboration; LSP gets them 0-based.
pub fn diagnose(source: String) -> List(Diagnostic) {
  let tokens = lexer.tokenize(source)
  case verify.parse_all_sexprs(tokens, []) {
    Error(e) -> [
      Diagnostic(line: e.line - 1, col: e.col - 1, message: e.message),
    ]
    Ok(exprs) ->
      case verify.terms_from_sexprs(exprs, []) {
        Error(e) -> [
          Diagnostic(line: e.line - 1, col: e.col - 1, message: e.message),
        ]
        Ok(terms) -> elaborate_diagnostics(terms)
      }
  }
}

fn elaborate_diagnostics(
  terms: List(elab_types.SurfaceTerm),
) -> List(Diagnostic) {
  let init_defs = verify.get_init_defs()
  let file_defs =
    list.filter_map(terms, fn(t) {
      case t {
        elab_types.SList([elab_types.SVar("define"), elab_types.SVar(name), val]) ->
          Ok(#(name, elab_types.SurfaceTermDef(val)))
        _ -> Error(Nil)
      }
    })
  let defs = list.append(file_defs, init_defs)
  let root = repl_eval.ref_for_name("lsp_diagnose")
  case
    elab.elaborate_unit(elab_types.SurfaceUnit(root:, defs:), empty_cache())
  {
    Ok(_) -> []
    Error(err) -> {
      let #(inner, span) = unwrap_at(err, None)
      let message = repl_eval.format_elab_error(inner, defs)
      case span {
        Some(s) -> [
          Diagnostic(line: s.line - 1, col: s.col - 1, message: message),
        ]
        None -> [Diagnostic(line: 0, col: 0, message: message)]
      }
    }
  }
}

fn unwrap_at(
  err: elab_types.ElaborateError,
  acc: Option(elab_types.Span),
) -> #(elab_types.ElaborateError, Option(elab_types.Span)) {
  case err {
    elab_types.At(inner, span) ->
      case acc {
        // Innermost span wins (same rule as elab_term's SLoc case).
        Some(_) -> unwrap_at(inner, acc)
        None -> unwrap_at(inner, Some(span))
      }
    other -> #(other, acc)
  }
}

fn jstr(s: String) -> String {
  let escaped =
    s
    |> string.replace("\\", "\\\\")
    |> string.replace("\"", "\\\"")
    |> string.replace("\n", "\\n")
    |> string.replace("\r", "\\r")
    |> string.replace("\t", "\\t")
  "\"" <> escaped <> "\""
}

// ── Language features: hover, definition, completion ───────────────────────
// All three are the same move: find the symbol at the position, then answer
// one question about it (its type / its origin / its siblings). The symbol
// walk uses the SLoc spans elaboration keeps; definition uses a text scan
// for the define form (the define's own SList carries no span today).

fn hover_reply(msg: Message, state: State) -> List(String) {
  case msg.id {
    None -> []
    Some(id) ->
      case symbol_under(msg.params, state) {
        Error(_) -> [respond(id, "null")]
        Ok(#(uri, name, _)) -> {
          let text = doc_text(state, uri)
          case hover_type(text, name) {
            Some(typ) -> [
              respond(
                id,
                "{\"contents\":{\"kind\":\"markdown\",\"value\":"
                  <> jstr("```gleamunison\n" <> name <> " : " <> typ <> "\n```")
                  <> "}}",
              ),
            ]
            None -> [
              respond(
                id,
                "{\"contents\":{\"kind\":\"markdown\",\"value\":"
                  <> jstr(name)
                  <> "}}",
              ),
            ]
          }
        }
      }
  }
}

fn definition_reply(msg: Message, state: State) -> List(String) {
  case msg.id {
    None -> []
    Some(id) ->
      case symbol_under(msg.params, state) {
        Error(_) -> [respond(id, "null")]
        Ok(#(uri, name, _)) ->
          case find_define_line(doc_text(state, uri), name) {
            Some(#(line0, col0)) -> [
              respond(
                id,
                "{\"uri\":"
                  <> jstr(uri)
                  <> ",\"range\":{\"start\":{\"line\":"
                  <> int.to_string(line0)
                  <> ",\"character\":"
                  <> int.to_string(col0)
                  <> "},\"end\":{\"line\":"
                  <> int.to_string(line0)
                  <> ",\"character\":"
                  <> int.to_string(col0 + string.length(name))
                  <> "}}}",
              ),
            ]
            None -> [respond(id, "null")]
          }
      }
  }
}

fn completion_reply(msg: Message, state: State) -> List(String) {
  case msg.id {
    None -> []
    Some(id) ->
      case position_of(msg.params) {
        Error(_) -> [respond(id, "null")]
        Ok(#(uri, line0, col0)) -> {
          let text = doc_text(state, uri)
          let prefix = word_before(text, line0, col0)
          let items =
            completion_names(text)
            |> list.filter(fn(n) { string.starts_with(n, prefix) })
            |> list.unique
            |> list.map(fn(n) { "{\"label\":" <> jstr(n) <> ",\"kind\":3}" })
          [
            respond(
              id,
              "{\"isIncomplete\":false,\"items\":["
                <> string.join(items, ",")
                <> "]}",
            ),
          ]
        }
      }
  }
}

fn doc_text(state: State, uri: String) -> String {
  case dict.get(state.docs, uri) {
    Ok(t) -> t
    Error(_) -> ""
  }
}

/// Decode textDocument.uri + position.{line,character}.
fn position_of(
  params: Dict(String, Dynamic),
) -> Result(#(String, Int, Int), Nil) {
  use doc_dyn <- result.try(dict.get(params, "textDocument"))
  let uri_decoder = {
    use uri <- decode.field("uri", decode.string)
    decode.success(uri)
  }
  use uri <- result.try(case decode.run(doc_dyn, uri_decoder) {
    Ok(u) -> Ok(u)
    Error(_) -> Error(Nil)
  })
  use pos_dyn <- result.try(dict.get(params, "position"))
  let pos_decoder = {
    use line <- decode.field("line", decode.int)
    use character <- decode.field("character", decode.int)
    decode.success(#(line, character))
  }
  use pos <- result.try(case decode.run(pos_dyn, pos_decoder) {
    Ok(p) -> Ok(p)
    Error(_) -> Error(Nil)
  })
  Ok(#(uri, pos.0, pos.1))
}

/// The symbol under the position: parse the doc, walk the SLoc spans,
/// take the var whose span covers (line, col). Spans are 1-based points;
/// the name's length gives the extent.
fn symbol_under(
  params: Dict(String, Dynamic),
  state: State,
) -> Result(#(String, String, Int), Nil) {
  use #(uri, line0, col0) <- result.try(position_of(params))
  let text = doc_text(state, uri)
  let vars = vars_in(text)
  let line = line0 + 1
  let col = col0 + 1
  use #(name, span) <- result.try(
    list.find(vars, fn(pair) {
      let #(n, s) = pair
      s.line == line && col >= s.col && col < s.col + string.length(n)
    })
    |> result.map_error(fn(_) { Nil }),
  )
  Ok(#(uri, name, span.col))
}

fn vars_in(text: String) -> List(#(String, elab_types.Span)) {
  let tokens = lexer.tokenize(text)
  case verify.parse_all_sexprs(tokens, []) {
    Error(_) -> []
    Ok(exprs) ->
      case verify.terms_from_sexprs(exprs, []) {
        Error(_) -> []
        Ok(terms) -> list.flat_map(terms, collect_vars(_, []))
      }
  }
}

fn collect_vars(
  term: elab_types.SurfaceTerm,
  acc: List(#(String, elab_types.Span)),
) -> List(#(String, elab_types.Span)) {
  case term {
    elab_types.SLoc(inner, span) ->
      case inner {
        elab_types.SVar(name) -> [#(name, span), ..collect_vars(inner, acc)]
        _ -> collect_vars(inner, acc)
      }
    elab_types.SApply(f, a) -> collect_vars(a, collect_vars(f, acc))
    elab_types.SList(items) ->
      list.fold(items, acc, fn(a, t) { collect_vars(t, a) })
    elab_types.SLambda(_, body) -> collect_vars(body, acc)
    elab_types.SLabeledFn(_, body) -> collect_vars(body, acc)
    elab_types.SLet(_, value, body) ->
      collect_vars(body, collect_vars(value, acc))
    elab_types.SUse(_, call, body) ->
      collect_vars(body, collect_vars(call, acc))
    elab_types.SMatch(scrutinee, cases) ->
      list.fold(cases, collect_vars(scrutinee, acc), fn(a, c) {
        let a = case c.guard {
          option.Some(g) -> collect_vars(g, a)
          _ -> a
        }
        collect_vars(c.body, a)
      })
    elab_types.SDo(_, _, args) ->
      list.fold(args, acc, fn(a, t) { collect_vars(t, a) })
    elab_types.SHandle(comp, handler, _) ->
      collect_vars(handler, collect_vars(comp, acc))
    _ -> acc
  }
}

/// The inferred type of a top-level def, when the file elaborates. Files
/// with errors still get a name-only hover — a partial answer beats none.
fn hover_type(text: String, name: String) -> option.Option(String) {
  let tokens = lexer.tokenize(text)
  case verify.parse_all_sexprs(tokens, []) {
    Error(_) -> option.None
    Ok(exprs) ->
      case verify.terms_from_sexprs(exprs, []) {
        Error(_) -> option.None
        Ok(terms) -> {
          let file_defs =
            list.filter_map(terms, fn(t) {
              case t {
                elab_types.SList([
                  elab_types.SVar("define"),
                  elab_types.SVar(n),
                  val,
                ]) -> Ok(#(n, elab_types.SurfaceTermDef(val)))
                _ -> Error(Nil)
              }
            })
          // Bootstrap first: file defs reference builtin names, so their
          // types must be in the cache before the file elaborates.
          let defs = list.append(verify.get_init_defs(), file_defs)
          let root = repl_eval.ref_for_name("lsp_hover")
          case
            elab.elaborate_unit(
              elab_types.SurfaceUnit(root:, defs:),
              repl_eval.seed_builtin_term_types(empty_cache()),
            )
          {
            Error(_) -> option.None
            Ok(#(unit, _, _)) ->
              case list.key_find(unit.defs, repl_eval.ref_for_name(name)) {
                Ok(ast.TermDef(_, typ)) ->
                  option.Some(type_pretty.pretty_print(typ))
                _ -> option.None
              }
          }
        }
      }
  }
}

/// Where is `name` defined? Text scan for the define form — the define's
/// own SList carries no span today, so the honest index is the source.
fn find_define_line(text: String, name: String) -> option.Option(#(Int, Int)) {
  string.split(text, "\n")
  |> list.index_map(fn(l, i) { #(i, l) })
  |> list.find_map(fn(pair) {
    let #(i, line) = pair
    case string.split_once(line, "(define " <> name) {
      Ok(#(before, _)) ->
        case string.trim(before) == "" {
          True -> Ok(#(i, string.length(before) + 9))
          False -> Error(Nil)
        }
      Error(_) -> Error(Nil)
    }
  })
  |> option.from_result
}

/// The word being completed: walk back from the cursor over symbol chars.
fn word_before(text: String, line0: Int, col0: Int) -> String {
  let lines = string.split(text, "\n")
  case list.drop(lines, line0) |> list.first {
    Error(_) -> ""
    Ok(line) -> {
      let before = string.slice(line, 0, col0)
      before
      |> string.to_graphemes
      |> list.reverse
      |> list.take_while(fn(g) {
        string.contains("abcdefghijklmnopqrstuvwxyz0123456789-_*?!<>+/", g)
      })
      |> list.reverse
      |> string.concat
    }
  }
}

/// Completion candidates: file-local def names plus every bootstrap name.
/// Text scan, not parse: the point of completion is that the document is
/// mid-edit and rarely parses. An incomplete line must not blind us.
fn completion_names(text: String) -> List(String) {
  let file_names =
    string.split(text, "\n")
    |> list.filter_map(fn(line) {
      case string.split_once(line, "(define ") {
        Ok(#(_, rest)) -> {
          let name =
            rest
            |> string.to_graphemes
            |> list.take_while(fn(g) {
              string.contains(
                "abcdefghijklmnopqrstuvwxyz0123456789-_*?!<>+/",
                g,
              )
            })
            |> string.concat
          case name {
            "" -> Error(Nil)
            _ -> Ok(name)
          }
        }
        Error(_) -> Error(Nil)
      }
    })
  let bootstrap_names = list.map(verify.get_init_defs(), fn(pair) { pair.0 })
  list.append(file_names, bootstrap_names)
}
