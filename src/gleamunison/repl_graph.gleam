//// REPL code-graph commands (roadmap 9.8): `view`, `dependents`,
//// `dependencies` — answered by the datalog codebase index, reusing the
//// MCP graph wiring. Pure text in / text out; the REPL loop prints the
//// result.

import gleam/list
import gleam/string
import gleamunison/ast
import gleamunison/codebase
import gleamunison/codebase_index
import gleamunison/elab_types.{type SurfaceDef}
import gleamunison/identity.{hash_to_debug_string}
import gleamunison/mcp_session
import gleamunison/test_runner
import gleamunison/type_pretty
import gleamunison/types

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

/// kind + content hash + name-ref + inferred type for one definition.
/// The hash is elaborated through the same path publish uses
/// (test_runner.elaborated_def_for), so the hash shown here is the hash
/// evidence attaches to — view and the turnstile agree by construction.
fn view(
  name: String,
  cache: types.TypeCache,
  defs: List(#(String, SurfaceDef)),
) -> String {
  case list.key_find(defs, name) {
    Error(_) -> name <> ": not found in this session"
    Ok(def) -> {
      let kind = codebase_index.kind_of(def)
      let refhex = codebase_index.ref_hex(name, def)
      case test_runner.elaborated_def_for(name, defs, cache) {
        Error(e) ->
          name
          <> "\n  kind: "
          <> kind
          <> "\n  ref: "
          <> refhex
          <> "\n  <elaboration failed: "
          <> e
          <> ">"
        Ok(elab_def) -> {
          let content =
            hash_to_debug_string(codebase.hash_of_definition(elab_def))
          let typ = case elab_def {
            ast.TermDef(_, t) -> type_pretty.pretty_print(t)
            _ -> "<unknown>"
          }
          name
          <> "\n  kind: "
          <> kind
          <> "\n  hash: "
          <> content
          <> "\n  ref: "
          <> refhex
          <> "\n  type: "
          <> typ
        }
      }
    }
  }
}
