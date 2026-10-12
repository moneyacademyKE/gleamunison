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
import gleamunison/elab_types
import gleamunison/elaborate as elab
import gleamunison/json
import gleamunison/lexer
import gleamunison/repl_eval
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
/// notifications) to frame and write. Empty list: nothing to say.
pub fn handle_message(body: String, state: String) -> List(String) {
  case json.decode(bit_array.from_string(body)) {
    Error(_) -> []
    Ok(dyn) ->
      case decode.run(dyn, message_decoder()) {
        Error(_) -> []
        Ok(msg) -> dispatch(msg, state)
      }
  }
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

fn dispatch(msg: Message, _state: String) -> List(String) {
  case msg.method {
    "initialize" ->
      case msg.id {
        Some(id) -> [respond(id, initialize_result())]
        None -> []
      }
    "initialized" -> []
    "shutdown" ->
      case msg.id {
        Some(id) -> [respond(id, "null")]
        None -> []
      }
    "exit" -> []
    "textDocument/didOpen" -> [diagnose_notification(msg.params, from_open)]
    "textDocument/didChange" -> [diagnose_notification(msg.params, from_change)]
    _ ->
      case msg.id {
        Some(id) -> [error_response(id, -32_601, "Method not found")]
        None -> []
      }
  }
}

fn initialize_result() -> String {
  "{\"capabilities\":{\"textDocumentSync\":1},"
  <> "\"serverInfo\":{\"name\":\"gleamunison\",\"version\":\"3.15.0\"}}"
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

fn diagnose_notification(
  params: Dict(String, Dynamic),
  is_open: Bool,
) -> String {
  case extract_doc(params, is_open) {
    Error(_) -> "{}"
    Ok(doc) -> {
      let diagnostics = diagnose(doc.text)
      publish(doc.uri, diagnostics)
    }
  }
}

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
