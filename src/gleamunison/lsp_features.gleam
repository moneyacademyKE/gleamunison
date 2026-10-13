//// LSP language features: hover, goto-definition, completion. Split from
//// lsp.gleam (protocol core) to keep both modules under the LOC ceiling.
//// The handlers are pure: message + doc store in, reply strings out.

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
import gleamunison/lexer
import gleamunison/lsp_types
import gleamunison/repl_eval
import gleamunison/type_pretty
import gleamunison/types.{empty_cache}
import gleamunison/verify

// ── Language features: hover, definition, completion ───────────────────────
// All three are the same move: find the symbol at the position, then answer
// one question about it (its type / its origin / its siblings). The symbol
// walk uses the SLoc spans elaboration keeps; definition uses a text scan
// for the define form (the define's own SList carries no span today).

pub fn hover_reply(msg: lsp_types.Message, state: lsp_types.State) -> List(String) {
  case msg.id {
    None -> []
    Some(id) ->
      case symbol_under(msg.params, state) {
        Error(_) -> [lsp_types.respond(id, "null")]
        Ok(#(uri, name, _)) -> {
          let text = doc_text(state, uri)
          case hover_type(text, name) {
            Some(typ) -> [
              lsp_types.respond(
                id,
                "{\"contents\":{\"kind\":\"markdown\",\"value\":"
                  <> lsp_types.jstr("```gleamunison\n" <> name <> " : " <> typ <> "\n```")
                  <> "}}",
              ),
            ]
            None -> [
              lsp_types.respond(
                id,
                "{\"contents\":{\"kind\":\"markdown\",\"value\":"
                  <> lsp_types.jstr(name)
                  <> "}}",
              ),
            ]
          }
        }
      }
  }
}

pub fn definition_reply(msg: lsp_types.Message, state: lsp_types.State) -> List(String) {
  case msg.id {
    None -> []
    Some(id) ->
      case symbol_under(msg.params, state) {
        Error(_) -> [lsp_types.respond(id, "null")]
        Ok(#(uri, name, _)) ->
          case find_define_line(doc_text(state, uri), name) {
            Some(#(line0, col0)) -> [
              lsp_types.respond(
                id,
                "{\"uri\":"
                  <> lsp_types.jstr(uri)
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
            None -> [lsp_types.respond(id, "null")]
          }
      }
  }
}

pub fn completion_reply(msg: lsp_types.Message, state: lsp_types.State) -> List(String) {
  case msg.id {
    None -> []
    Some(id) ->
      case position_of(msg.params) {
        Error(_) -> [lsp_types.respond(id, "null")]
        Ok(#(uri, line0, col0)) -> {
          let text = doc_text(state, uri)
          let prefix = word_before(text, line0, col0)
          let items =
            completion_names(text)
            |> list.filter(fn(n) { string.starts_with(n, prefix) })
            |> list.unique
            |> list.map(fn(n) { "{\"label\":" <> lsp_types.jstr(n) <> ",\"kind\":3}" })
          [
            lsp_types.respond(
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

fn doc_text(state: lsp_types.State, uri: String) -> String {
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
  state: lsp_types.State,
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
