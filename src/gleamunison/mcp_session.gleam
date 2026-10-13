//// MCP session layer: a live gleamunison session behind the JSON-RPC tools.
////
//// The session is immutable after boot: `eval` is read-only (define forms are
//// rejected), so handlers never thread state. Tools answer from the session's
//// own definition table — names, kinds, content-addressed refs.

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/float
import gleam/list
import gleam/order
import gleam/result
import gleam/string
import gleamunison/codebase_index
import gleamunison/elab_types.{
  type SurfaceDef, SurfaceAbilityDef, SurfacePubTypeAlias, SurfaceTermDef,
  SurfaceTypeAlias, SurfaceTypeDef,
}
import gleamunison/identity.{type DefinitionRef, Ref, hash_to_debug_string}
import gleamunison/lexer
import gleamunison/mcp.{type Response, type Tool, Server, Tool}
import gleamunison/parser
import gleamunison/rank
import gleamunison/repl_eval
import gleamunison/type_pretty
import gleamunison/types.{type TypeCache, empty_cache}
import gleamunison/verify
import simplifile

// Keep in step with gleam.toml at release time.
const server_version = "3.17.0"

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

/// The session's definition set (name + surface def). Read-only view for
/// index tooling and diagnostics.
pub fn session_defs(state: SessionState) -> List(#(String, SurfaceDef)) {
  state.defs
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
    Tool(
      name: "callers_of",
      description: "List definitions that reference the given name (datalog index)",
      handler: fn(args) {
        case string_arg(args, "name") {
          Error(e) -> Error(e)
          Ok(name) ->
            result.map(callers_of(state, name), fn(ns) { names_json(ns) })
        }
      },
    ),
    Tool(
      name: "deps_of",
      description: "List in-corpus names the given definition references",
      handler: fn(args) {
        case string_arg(args, "name") {
          Error(e) -> Error(e)
          Ok(name) ->
            result.map(deps_of(state, name), fn(ns) { names_json(ns) })
        }
      },
    ),
    Tool(
      name: "defs_by_kind",
      description: "List definitions of a kind (term, type, ability, type-alias)",
      handler: fn(args) {
        case string_arg(args, "kind") {
          Error(e) -> Error(e)
          Ok(k) -> result.map(defs_by_kind(state, k), fn(ns) { names_json(ns) })
        }
      },
    ),
  ]
}

fn names_json(names: List(String)) -> String {
  let parts = list.map(names, fn(n) { "\"" <> n <> "\"" })
  "[" <> string.join(parts, ",") <> "]"
}

/// Callers of a name: every definition with a def/dep edge pointing at it.
/// Answered by the native datalog engine over the session index.
pub fn callers_of(
  state: SessionState,
  name: String,
) -> Result(List(String), String) {
  index_names(
    state,
    "\n(define q (list (pair (q-var \"?e\") (pair \"def/dep\" (q-val \""
      <> name
      <> "\"))) (pair (q-var \"?e\") (pair \"def/name\" (q-var \"?n\")))))\n(binding-values (db-query db q) \"?n\")\n",
  )
}

/// Dependencies of a definition: in-corpus names its body references.
pub fn deps_of(
  state: SessionState,
  name: String,
) -> Result(List(String), String) {
  index_names(
    state,
    "\n(define q (list (pair (q-var \"?e\") (pair \"def/name\" (q-val \""
      <> name
      <> "\"))) (pair (q-var \"?e\") (pair \"def/dep\" (q-var \"?d\")))))\n(binding-values (db-query db q) \"?d\")\n",
  )
}

/// Definitions filtered by kind (term, type, ability, type-alias).
pub fn defs_by_kind(
  state: SessionState,
  kind: String,
) -> Result(List(String), String) {
  index_names(
    state,
    "\n(define q (list (pair (q-var \"?e\") (pair \"def/kind\" (q-val \""
      <> kind
      <> "\"))) (pair (q-var \"?e\") (pair \"def/name\" (q-var \"?n\")))))\n(binding-values (db-query db q) \"?n\")\n",
  )
}

/// Run a query tail against the session's datalog index; extract the quoted
/// strings from the final form's printed value.
fn index_names(
  state: SessionState,
  tail: String,
) -> Result(List(String), String) {
  let script = codebase_index.index_source(state.defs) <> tail
  case codebase_index.eval_index_source(script) {
    Error(e) -> Error(e)
    Ok(out) -> {
      // Engine define forms print as `(defined name)` — no quotes — so every
      // quoted string in the output belongs to the final result value. Scan
      // all lines: long result lists wrap across them.
      Ok(extract_quoted(out, False, "", []))
    }
  }
}

/// Pull every "..."-quoted string out of a printed value. Robust to either
/// list shape the runtime prints.
fn extract_quoted(
  s: String,
  in_str: Bool,
  cur: String,
  acc: List(String),
) -> List(String) {
  case string.pop_grapheme(s) {
    Error(_) ->
      case in_str {
        True -> list.reverse([cur, ..acc])
        False -> list.reverse(acc)
      }
    Ok(#("\\", rest)) ->
      case string.pop_grapheme(rest) {
        Ok(#(g, rest2)) -> extract_quoted(rest2, in_str, cur <> g, acc)
        Error(_) -> list.reverse(acc)
      }
    Ok(#("\"", rest)) ->
      case in_str {
        True -> extract_quoted(rest, False, "", [cur, ..acc])
        False -> extract_quoted(rest, True, "", acc)
      }
    Ok(#(g, rest)) ->
      case in_str {
        True -> extract_quoted(rest, True, cur <> g, acc)
        False -> extract_quoted(rest, False, cur, acc)
      }
  }
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
      <> "\",\"score\":"
      <> float.to_string(h.score)
      <> "}"
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
  SearchHit(name: String, kind: String, ref_hex: String, score: Float)
}

/// BM25-ranked search over definition names and bodies. Name tokens count
/// double (a name match is stronger intent evidence than a body mention).
/// Ties break alphabetically for stable output.
pub fn search(state: SessionState, query: String) -> List(SearchHit) {
  let scored =
    rank.rank_hybrid(
      query,
      list.map(state.defs, fn(pair) {
        rank.DocV(
          id: pair,
          // Name twice: a name match is stronger intent evidence than a
          // body mention (mirrors the BM25 weighting this replaces).
          text: pair.0
            <> " "
            <> pair.0
            <> " "
            <> string.join(def_body_tokens(pair.1), " "),
        )
      }),
    )
  let sorted =
    list.sort(scored, fn(a, b) {
      case float.compare(b.0, a.0) {
        order.Eq -> string.compare(a.1.0, b.1.0)
        o -> o
      }
    })
  list.map(sorted, fn(pair) {
    let def_pair = pair.1
    SearchHit(
      name: def_pair.0,
      kind: codebase_index.kind_of(def_pair.1),
      ref_hex: codebase_index.ref_hex(def_pair.0, def_pair.1),
      score: pair.0,
    )
  })
}

/// The searchable corpus of a definition: the program's own words — names,
/// text literals, constructor names — never debug serialization (inspect
/// renders ref internals like `Hash(...)`, which would put the token "hash"
/// in every document) and never span coordinates.
fn def_body_tokens(def: SurfaceDef) -> List(String) {
  case def {
    SurfaceTermDef(term) -> term_tokens(term)
    _ -> []
  }
}

fn term_tokens(term: elab_types.SurfaceTerm) -> List(String) {
  case term {
    elab_types.SLoc(inner, _) -> term_tokens(inner)
    elab_types.SVar(name) -> rank.tokenize(name)
    elab_types.SText(bytes) ->
      case bit_array.to_string(bytes) {
        Ok(s) -> rank.tokenize(s)
        Error(_) -> []
      }
    elab_types.SApply(f, a) -> list.append(term_tokens(f), term_tokens(a))
    elab_types.SLambda(param, body) ->
      list.append(rank.tokenize(param), term_tokens(body))
    elab_types.SLet(name, value, body) ->
      list.append(
        rank.tokenize(name),
        list.append(term_tokens(value), term_tokens(body)),
      )
    elab_types.SMatch(scrutinee, cases) ->
      list.append(
        term_tokens(scrutinee),
        list.flat_map(cases, fn(c) { term_tokens(c.body) }),
      )
    elab_types.SDo(ability, op, args) ->
      list.append(
        rank.tokenize(ability),
        list.append(rank.tokenize(op), list.flat_map(args, term_tokens)),
      )
    elab_types.SConstruct(name, args) ->
      list.append(rank.tokenize(name), list.flat_map(args, term_tokens))
    elab_types.SHandle(comp, handler, ability) ->
      list.append(
        term_tokens(comp),
        list.append(term_tokens(handler), rank.tokenize(ability)),
      )
    elab_types.SLabeledFn(params, body) ->
      list.append(
        list.flat_map(params, fn(p) {
          list.append(rank.tokenize(p.0), term_tokens(p.1))
        }),
        term_tokens(body),
      )
    elab_types.SUse(binder, call, body) ->
      list.append(
        rank.tokenize(binder),
        list.append(term_tokens(call), term_tokens(body)),
      )
    elab_types.SList(items) -> list.flat_map(items, term_tokens)
    _ -> []
  }
}

fn defs_json(defs: List(#(String, SurfaceDef))) -> String {
  let parts = list.map(defs, fn(pair) { def_json(pair.0, pair.1) })
  "[" <> string.join(parts, ",") <> "]"
}

fn def_json(name: String, def: SurfaceDef) -> String {
  "{\"name\":\""
  <> name
  <> "\",\"kind\":\""
  <> codebase_index.kind_of(def)
  <> "\",\"ref\":\""
  <> codebase_index.ref_hex(name, def)
  <> "\"}"
}

fn ref_to_hex(r: DefinitionRef) -> String {
  let Ref(h) = r
  hash_to_debug_string(h)
}
