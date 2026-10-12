//// MCP session layer: a live gleamunison session behind the JSON-RPC tools.
////
//// The session is immutable after boot: `eval` is read-only (define forms are
//// rejected), so handlers never thread state. Tools answer from the session's
//// own definition table — names, kinds, content-addressed refs.

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import gleam/order
import gleam/string
import gleamunison/elab_types.{
  type SurfaceDef, SurfaceAbilityDef, SurfacePubTypeAlias, SurfaceTermDef,
  SurfaceTypeAlias, SurfaceTypeDef,
}
import gleamunison/identity.{type DefinitionRef, Ref, hash_to_debug_string}
import gleamunison/lexer
import gleamunison/mcp.{type Response, type Tool, Server, Tool}
import gleamunison/parser
import gleamunison/repl_eval
import gleamunison/type_pretty
import gleamunison/types.{type TypeCache, empty_cache}
import gleamunison/verify
import simplifile

// Keep in step with gleam.toml at release time.
const server_version = "3.14.0"

pub opaque type SessionState {
  SessionState(cache: TypeCache, defs: List(#(String, SurfaceDef)))
}

/// Fresh session: bootstrap (genesis) definitions only.
pub fn boot() -> SessionState {
  let #(cache, defs) =
    repl_eval.bootstrap_defs(verify.get_init_defs(), empty_cache())
  SessionState(cache, defs)
}

/// Extend a session by loading a lisp source file through the same
/// pipeline `verify` uses: defines are defined, other forms evaluated.
pub fn load_file(
  state: SessionState,
  path: String,
) -> Result(SessionState, String) {
  case simplifile.read(path) {
    Error(_) -> Error("cannot read file: " <> path)
    Ok(content) -> {
      let tokens = lexer.tokenize(content)
      case verify.parse_all_sexprs(tokens, []) {
        Error(e) -> Error("parse error in " <> path <> ": " <> e.message)
        Ok(exprs) ->
          case verify.terms_from_sexprs(exprs, []) {
            Error(e) -> Error("sexpr error in " <> path <> ": " <> e.message)
            Ok(terms) -> eval_terms(state, terms)
          }
      }
    }
  }
}

fn eval_terms(
  state: SessionState,
  terms: List(elab_types.SurfaceTerm),
) -> Result(SessionState, String) {
  case terms {
    [] -> Ok(state)
    [term, ..rest] -> {
      case term {
        elab_types.SList([elab_types.SVar("define"), elab_types.SVar(name), val]) ->
          case repl_eval.handle_define(name, val, state.cache, state.defs) {
            Ok(#(cache, defs)) -> eval_terms(SessionState(cache, defs), rest)
            Error(err) -> Error("define " <> name <> ": " <> err)
          }
        _ ->
          case repl_eval.do_eval(term, "mcp_boot", state.cache, state.defs) {
            Ok(#(_, _, cache)) ->
              eval_terms(SessionState(..state, cache: cache), rest)
            Error(err) -> Error("eval: " <> err)
          }
      }
    }
  }
}

/// Route one JSON-RPC body through the protocol layer with the session's
/// real tools attached.
pub fn handle_rpc(state: SessionState, body: String) -> Response {
  let server =
    Server(name: "gleamunison", version: server_version, tools: tools(state))
  mcp.handle_message(server, body)
}

fn tools(state: SessionState) -> List(Tool) {
  [
    Tool(
      name: "list_definitions",
      description: "List every definition in the session (name, kind, ref)",
      handler: fn(_) { Ok(defs_json(state.defs)) },
    ),
    Tool(
      name: "get_definition",
      description: "Fetch one definition by exact name",
      handler: fn(args) { get_definition(state, args) },
    ),
    Tool(
      name: "search_definitions",
      description: "Substring search over definition names and bodies",
      handler: fn(args) { search_definitions(state, args) },
    ),
    Tool(
      name: "eval",
      description: "Evaluate a read-only S-expression against the session",
      handler: fn(args) { eval_tool(state, args) },
    ),
  ]
}

fn get_definition(
  state: SessionState,
  args: Dict(String, Dynamic),
) -> Result(String, String) {
  case string_arg(args, "name") {
    Error(e) -> Error(e)
    Ok(name) ->
      case list.key_find(state.defs, name) {
        Error(_) -> Error("definition not found: " <> name)
        Ok(def) -> Ok(def_json(name, def))
      }
  }
}

fn search_definitions(
  state: SessionState,
  args: Dict(String, Dynamic),
) -> Result(String, String) {
  case string_arg(args, "query") {
    Error(e) -> Error(e)
    Ok(query) -> Ok(hits_json(search(state, query)))
  }
}

fn hits_json(hits: List(SearchHit)) -> String {
  let parts =
    list.map(hits, fn(h) {
      "{\"name\":\""
      <> h.name
      <> "\",\"kind\":\""
      <> h.kind
      <> "\",\"ref\":\""
      <> h.ref_hex
      <> "\"}"
    })
  "[" <> string.join(parts, ",") <> "]"
}

fn eval_tool(
  state: SessionState,
  args: Dict(String, Dynamic),
) -> Result(String, String) {
  case string_arg(args, "expr") {
    Error(e) -> Error(e)
    Ok(expr) ->
      case parser.parse_string(expr) {
        Error(e) -> Error("parse error: " <> e.message)
        Ok(elab_types.SList([
          elab_types.SVar("define"),
          elab_types.SVar(name),
          _,
        ])) -> Error("define not allowed via MCP eval (read-only): " <> name)
        Ok(term) ->
          case repl_eval.do_eval(term, "mcp_eval", state.cache, state.defs) {
            Ok(#(val_str, typ, _)) ->
              Ok(val_str <> " : " <> type_pretty.pretty_print(typ))
            Error(err) -> Error(err)
          }
      }
  }
}

fn string_arg(
  args: Dict(String, Dynamic),
  key: String,
) -> Result(String, String) {
  case dict.get(args, key) {
    Error(_) -> Error("missing argument: " <> key)
    Ok(dyn) ->
      case decode.run(dyn, decode.string) {
        Ok(s) -> Ok(s)
        Error(_) -> Error("argument must be a string: " <> key)
      }
  }
}

/// One search hit: the triple a CLI or an agent actually needs.
pub type SearchHit {
  SearchHit(name: String, kind: String, ref_hex: String)
}

/// Substring search over definition names and bodies. Name matches rank
/// above body-only matches; alphabetical inside groups.
pub fn search(state: SessionState, query: String) -> List(SearchHit) {
  let matches =
    list.filter(state.defs, fn(pair) {
      string.contains(pair.0, query)
      || string.contains(string.inspect(pair.1), query)
    })
  let ranked =
    list.sort(matches, fn(a, b) {
      let an = string.contains(a.0, query)
      let bn = string.contains(b.0, query)
      case an, bn {
        True, False -> order.Lt
        False, True -> order.Gt
        _, _ -> string.compare(a.0, b.0)
      }
    })
  list.map(ranked, fn(pair) {
    SearchHit(
      name: pair.0,
      kind: kind(pair.1),
      ref_hex: ref_hex(pair.0, pair.1),
    )
  })
}

fn defs_json(defs: List(#(String, SurfaceDef))) -> String {
  let parts = list.map(defs, fn(pair) { def_json(pair.0, pair.1) })
  "[" <> string.join(parts, ",") <> "]"
}

fn def_json(name: String, def: SurfaceDef) -> String {
  "{\"name\":\""
  <> name
  <> "\",\"kind\":\""
  <> kind(def)
  <> "\",\"ref\":\""
  <> ref_hex(name, def)
  <> "\"}"
}

fn kind(def: SurfaceDef) -> String {
  case def {
    SurfaceTermDef(_) -> "term"
    SurfaceTypeDef(_) -> "type"
    SurfaceAbilityDef(_, _) -> "ability"
    SurfaceTypeAlias(_, _) -> "type-alias"
    SurfacePubTypeAlias(_, _) -> "type-alias"
  }
}

fn ref_hex(name: String, def: SurfaceDef) -> String {
  case def {
    SurfaceTermDef(elab_types.SRef(r)) -> ref_to_hex(r)
    _ -> ref_to_hex(repl_eval.ref_for_name(name))
  }
}

fn ref_to_hex(r: DefinitionRef) -> String {
  let Ref(h) = r
  hash_to_debug_string(h)
}
