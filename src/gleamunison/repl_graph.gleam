//// REPL code-graph commands (roadmap 9.8): `view`, `dependents`,
//// `dependencies` — answered by the datalog codebase index, reusing the
//// MCP graph wiring. Pure text in / text out; the REPL loop prints the
//// result.

import gleam/list
import gleam/string
import gleamunison/ast
import gleamunison/codebase_index
import gleamunison/elab_types.{type SurfaceDef}
import gleamunison/elaborate as elab
import gleamunison/mcp_session
import gleamunison/repl_eval
import gleamunison/type_pretty
import gleamunison/types
import gleamunison/verify

/// Handle a graph command, or pass through with Error(Nil) when the input
/// is not one. Ok(output) includes usage errors for known command words.
pub fn try_handle(
  input: String,
  cache: types.TypeCache,
  defs: List(#(String, SurfaceDef)),
) -> Result(String, Nil) {
  case string.split(input, " ") {
    ["view", name] -> Ok(view(name, cache, defs))
    ["dependents", name] ->
      Ok(names_or_err(mcp_session.callers_of(session(cache, defs), name)))
    ["dependencies", name] ->
      Ok(names_or_err(mcp_session.deps_of(session(cache, defs), name)))
    ["view"] | ["dependents"] | ["dependencies"] ->
      Ok("usage: view <name> | dependents <name> | dependencies <name>")
    _ -> Error(Nil)
  }
}

fn session(
  cache: types.TypeCache,
  defs: List(#(String, SurfaceDef)),
) -> mcp_session.SessionState {
  mcp_session.from_parts(cache, defs)
}

fn names_or_err(result: Result(List(String), String)) -> String {
  case result {
    Ok([]) -> "(none)"
    Ok(names) -> string.join(names, "\n")
    Error(err) -> "index error: " <> err
  }
}

/// kind + content hash + inferred type for one definition.
fn view(
  name: String,
  _cache: types.TypeCache,
  defs: List(#(String, SurfaceDef)),
) -> String {
  case list.key_find(defs, name) {
    Error(_) -> name <> ": not found in this session"
    Ok(def) -> {
      let kind = codebase_index.kind_of(def)
      let hash = codebase_index.ref_hex(name, def)
      let typ = view_type(name, defs)
      name
      <> "\n  kind: "
      <> kind
      <> "\n  hash: "
      <> hash
      <> "\n  type: "
      <> typ
    }
  }
}

fn view_type(name: String, defs: List(#(String, SurfaceDef))) -> String {
  // Bootstrap first: session defs may reference builtin names.
  let all_defs = list.append(verify.get_init_defs(), defs)
  let root = repl_eval.ref_for_name("repl_view")
  case
    elab.elaborate_unit(
      elab_types.SurfaceUnit(root:, defs: all_defs),
      repl_eval.seed_builtin_term_types(types.empty_cache()),
    )
  {
    Error(_) -> "<untypable in this session>"
    Ok(#(unit, _, _)) ->
      case list.key_find(unit.defs, repl_eval.ref_for_name(name)) {
        Ok(ast.TermDef(_, typ)) -> type_pretty.pretty_print(typ)
        _ -> "<unknown>"
      }
  }
}
