//// MCP session layer: selected-branch CAS plus explicit source overlays.
//// The pure session owns values; the supervised web session owns mutations.

import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleamunison/active_storage
import gleamunison/agent_read_model
import gleamunison/cli_lifecycle
import gleamunison/codebase_graph
import gleamunison/elab_types.{type SurfaceDef}
import gleamunison/identity
import gleamunison/lexer
import gleamunison/mcp.{type Response, type Tool, Server, Tool}
import gleamunison/mcp_definition
import gleamunison/mcp_generation
import gleamunison/mcp_search
import gleamunison/mcp_tools
import gleamunison/mcp_write
import gleamunison/parser
import gleamunison/repl_eval
import gleamunison/storage
import gleamunison/type_pretty
import gleamunison/types.{type TypeCache, TypeCache, empty_cache}
import gleamunison/verify
import gleamunison/version
import simplifile

pub opaque type SessionState {
  SessionState(
    cache: TypeCache,
    defs: List(#(String, SurfaceDef)),
    entries: List(agent_read_model.Entry),
    selection: Option(agent_read_model.Selection),
  )
}

/// Server startup reads the configured branch and the node's one active store.
pub fn boot_configured() -> Result(SessionState, String) {
  use adapter <- result.try(active_storage.active_or_open())
  use branch <- result.try(cli_lifecycle.resolve_branch())
  from_store(adapter, branch)
}

pub fn from_store(
  adapter: storage.StorageAdapter,
  branch: String,
) -> Result(SessionState, String) {
  let base = boot()
  use #(stored, selection) <- result.try(agent_read_model.load(adapter, branch))
  let entries = unique_entries(list.append(stored, base.entries))
  Ok(SessionState(
    cache: agent_read_model.cache(entries, base.cache),
    defs: agent_read_model.definitions(entries),
    entries:,
    selection: Some(selection),
  ))
}

/// Fresh scratch-only session: bootstrap definitions, no ambient store.
pub fn boot() -> SessionState {
  let #(cache, defs) =
    repl_eval.bootstrap_defs(verify.get_init_defs(), empty_cache())
  let entries =
    list.map(defs, fn(pair) {
      agent_read_model.Source(pair.0, pair.1, agent_read_model.Bootstrap)
    })
  SessionState(cache, defs, entries, None)
}

/// Explicit scratch view for the REPL and isolated tests.
pub fn from_parts(
  cache: TypeCache,
  defs: List(#(String, SurfaceDef)),
) -> SessionState {
  let entries =
    list.map(defs, fn(pair) {
      agent_read_model.Source(pair.0, pair.1, agent_read_model.Scratch)
    })
  SessionState(cache, defs, entries, None)
}

/// Rebuild a durable snapshot, then reapply only the previous scratch overlay.
/// A successful write must not turn the session into a second scratch owner or
/// silently discard unrelated exploratory definitions.
pub fn overlay_scratch(
  fresh: SessionState,
  previous: SessionState,
) -> SessionState {
  let scratch =
    list.filter(previous.entries, fn(entry) {
      agent_read_model.origin(entry) == agent_read_model.Scratch
    })
  let entries = unique_entries(list.append(scratch, fresh.entries))
  let cache =
    list.fold(
      scratch,
      TypeCache(dict.merge(previous.cache.entries, fresh.cache.entries)),
      fn(cache, entry) {
        let name_ref = identity.name_ref(agent_read_model.name(entry))
        case dict.get(previous.cache.entries, name_ref) {
          Ok(computed) ->
            TypeCache(dict.insert(cache.entries, name_ref, computed))
          Error(_) -> cache
        }
      },
    )
  SessionState(
    cache:,
    defs: agent_read_model.definitions(entries),
    entries:,
    selection: fresh.selection,
  )
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

/// Every name the session can resolve: the baseline plus whatever a define bound.
/// Sorted, so a listing does not change order between requests.
fn visible_entries(state: SessionState) -> List(agent_read_model.Entry) {
  unique_entries(state.entries)
}

fn unique_entries(
  entries: List(agent_read_model.Entry),
) -> List(agent_read_model.Entry) {
  unique_entries_into(entries, dict.new(), [])
}

fn unique_entries_into(
  entries: List(agent_read_model.Entry),
  seen: Dict(String, Nil),
  acc: List(agent_read_model.Entry),
) -> List(agent_read_model.Entry) {
  case entries {
    [] -> list.reverse(acc)
    [entry, ..rest] -> {
      let name = agent_read_model.name(entry)
      case dict.has_key(seen, name) {
        True -> unique_entries_into(rest, seen, acc)
        False ->
          unique_entries_into(rest, dict.insert(seen, name, Nil), [entry, ..acc])
      }
    }
  }
}

fn find_entry(
  state: SessionState,
  name: String,
) -> Result(agent_read_model.Entry, Nil) {
  list.find(visible_entries(state), fn(entry) {
    agent_read_model.name(entry) == name
  })
}

fn with_defs(
  state: SessionState,
  cache: TypeCache,
  defs: List(#(String, SurfaceDef)),
) -> SessionState {
  let current = visible_entries(state)
  let by_name =
    list.fold(current, dict.new(), fn(acc, entry) {
      dict.insert(acc, agent_read_model.name(entry), entry)
    })
  let entries =
    list.map(defs, fn(pair) {
      case dict.get(by_name, pair.0) {
        Ok(entry) ->
          case agent_read_model.projection(entry) {
            Ok(current) if current == pair -> entry
            _ ->
              agent_read_model.Source(pair.0, pair.1, agent_read_model.Scratch)
          }
        Error(_) ->
          agent_read_model.Source(pair.0, pair.1, agent_read_model.Scratch)
      }
    })
  // Stored types and abilities deliberately have no surface projection. Keep
  // them when term elaboration returns its narrower definition list.
  let unprojected =
    list.filter(current, fn(entry) {
      case agent_read_model.projection(entry) {
        Ok(_) -> False
        Error(_) -> True
      }
    })
  SessionState(
    ..state,
    cache:,
    defs:,
    entries: unique_entries(list.append(entries, unprojected)),
  )
}

/// Every visible name in the durable view plus its explicit scratch overlay.
pub fn defined_names(state: SessionState) -> List(String) {
  visible_entries(state)
  |> list.map(agent_read_model.name)
  |> list.sort(string.compare)
}

/// Evaluate source against the session and return the last value plus the
/// advanced state. This is the live-session contract the REPL and the HTTP
/// routes share: a `define` binds a name for later evaluation, anything else
/// is an expression. The HTTP surface used to call a stateless evaluator with
/// no baseline, so `/eval?expr=(+ 1 2)` answered "undefined variable `+`" and
/// `/define` stored the source text in a notebook without binding anything —
/// the route said "defined" and nothing was.
pub fn eval_source(
  state: SessionState,
  source: String,
) -> Result(#(String, SessionState), String) {
  let tokens = lexer.tokenize(source)
  use exprs <- result.try(
    verify.parse_all_sexprs(tokens, [])
    |> result.map_error(fn(e) { "parse error: " <> e.message }),
  )
  use terms <- result.try(
    verify.terms_from_sexprs(exprs, [])
    |> result.map_error(fn(e) { "sexpr error: " <> e.message }),
  )
  eval_terms_collecting(state, terms, "")
}

/// Bind one definition by name, so a later `eval` sees it.
pub fn define_source(
  state: SessionState,
  name: String,
  source: String,
) -> Result(#(String, SessionState), String) {
  eval_source(state, "(define " <> name <> " " <> source <> ")")
}

fn eval_terms_collecting(
  state: SessionState,
  terms: List(elab_types.SurfaceTerm),
  last: String,
) -> Result(#(String, SessionState), String) {
  case terms {
    [] -> Ok(#(last, state))
    [term, ..rest] -> {
      case term {
        elab_types.SList([elab_types.SVar("define"), elab_types.SVar(name), val]) ->
          case repl_eval.handle_define(name, val, state.cache, state.defs) {
            Ok(#(cache, defs)) ->
              eval_terms_collecting(with_defs(state, cache, defs), rest, name)
            Error(err) -> Error("define " <> name <> ": " <> err)
          }
        _ ->
          case
            repl_eval.do_eval(term, "session_expr", state.cache, state.defs)
          {
            Ok(#(value, _, cache)) ->
              eval_terms_collecting(
                SessionState(..state, cache: cache),
                rest,
                value,
              )
            Error(err) -> Error("eval: " <> err)
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
            Ok(#(cache, defs)) ->
              eval_terms(with_defs(state, cache, defs), rest)
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
    Server(name: "gleamunison", version: version.current(), tools: tools(state))
  mcp.handle_message(server, body)
}

pub fn definitions_json(state: SessionState) -> String {
  mcp_definition.defs_json(state.cache, visible_entries(state))
}

fn tools(state: SessionState) -> List(Tool) {
  [
    Tool(
      name: "list_definitions",
      description: "List every definition in the session (name, kind, ref)",
      handler: fn(_) { Ok(definitions_json(state)) },
    ),
    Tool(
      name: "get_definition",
      description: "Fetch one definition by exact name",
      handler: fn(args) {
        use name <- result.try(mcp_tools.string_arg(args, "name"))
        get_definition(state, name)
      },
    ),
    Tool(
      name: "search_definitions",
      description: "Substring search over definition names and bodies",
      handler: fn(args) {
        use query <- result.try(mcp_tools.string_arg(args, "query"))
        search_definitions(state, query)
      },
    ),
    Tool(
      name: "eval",
      description: "Evaluate a read-only S-expression against the session",
      handler: fn(args) {
        use expression <- result.try(mcp_tools.string_arg(args, "expr"))
        eval_tool(state, expression)
      },
    ),
    mcp_write.tool(),
    mcp_generation.tool(),
    names_tool("callers_of", "name", callers_of(state, _)),
    names_tool("deps_of", "name", deps_of(state, _)),
    names_tool("defs_by_kind", "kind", defs_by_kind(state, _)),
  ]
}

fn names_tool(
  name: String,
  argument: String,
  query: fn(String) -> Result(List(String), String),
) -> Tool {
  let description = case name {
    "callers_of" -> "List definitions that reference the given name"
    "deps_of" -> "List in-corpus names the given definition references"
    _ -> "List definitions of a kind (term, type, ability, type-alias)"
  }
  Tool(name:, description:, handler: fn(args) {
    use value <- result.try(mcp_tools.string_arg(args, argument))
    result.map(query(value), mcp_tools.names_json)
  })
}

/// Callers of a name: every visible definition with a dependency edge to it.
pub fn callers_of(
  state: SessionState,
  name: String,
) -> Result(List(String), String) {
  Ok(codebase_graph.callers_of(visible_entries(state), name))
}

/// Dependencies of a definition: in-corpus names its body references.
pub fn deps_of(
  state: SessionState,
  name: String,
) -> Result(List(String), String) {
  Ok(codebase_graph.deps_of(visible_entries(state), name))
}

/// Definitions filtered by kind (term, type, ability, type-alias).
pub fn defs_by_kind(
  state: SessionState,
  kind: String,
) -> Result(List(String), String) {
  Ok(codebase_graph.defs_by_kind(visible_entries(state), kind))
}

fn get_definition(state: SessionState, name: String) -> Result(String, String) {
  case find_entry(state, name) {
    Error(_) -> Error("definition not found: " <> name)
    Ok(entry) -> Ok(mcp_definition.json(state.cache, state.defs, entry))
  }
}

fn search_definitions(
  state: SessionState,
  query: String,
) -> Result(String, String) {
  Ok(mcp_search.hits_json(search(state, query)))
}

pub type SearchHit =
  mcp_search.SearchHit

pub fn search(state: SessionState, query: String) -> List(SearchHit) {
  mcp_search.search(state.cache, state.defs, visible_entries(state), query)
}

fn eval_tool(state: SessionState, expr: String) -> Result(String, String) {
  case parser.parse_string(expr) {
    Error(e) -> Error("parse error: " <> e.message)
    Ok(elab_types.SList([elab_types.SVar("define"), elab_types.SVar(name), _])) ->
      Error("define not allowed via MCP eval (read-only): " <> name)
    Ok(term) ->
      case repl_eval.do_eval(term, "mcp_eval", state.cache, state.defs) {
        Ok(#(val_str, typ, _)) ->
          Ok(val_str <> " : " <> type_pretty.pretty_print(typ))
        Error(err) -> Error(err)
      }
  }
}
