//// Agent-facing definition identity: `ref` is stored/elaborated content;
//// `name_ref` is the distinct dependency/module handle. Origin is explicit.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleamunison/agent_read_model.{type Entry}
import gleamunison/codebase
import gleamunison/codebase_index
import gleamunison/elab_types.{type SurfaceDef}
import gleamunison/identity
import gleamunison/mcp
import gleamunison/test_runner
import gleamunison/types.{type TypeCache}

pub fn content_hex(
  cache: TypeCache,
  defs: List(#(String, SurfaceDef)),
  entry: Entry,
) -> Option(String) {
  case agent_read_model.stored_ref(entry) {
    Some(ref) -> {
      let identity.Ref(hash) = ref
      Some(identity.hash_to_debug_string(hash))
    }
    None ->
      case
        test_runner.elaborated_def_for(
          agent_read_model.name(entry),
          defs,
          cache,
        )
      {
        Error(_) -> None
        Ok(definition) ->
          Some(
            identity.hash_to_debug_string(codebase.hash_of_definition(
              definition,
            )),
          )
      }
  }
}

pub fn defs_json(cache: TypeCache, entries: List(Entry)) -> String {
  let defs = agent_read_model.definitions(entries)
  let parts = list.map(entries, fn(entry) { json(cache, defs, entry) })
  "[" <> string.join(parts, ",") <> "]"
}

pub fn json(
  cache: TypeCache,
  defs: List(#(String, SurfaceDef)),
  entry: Entry,
) -> String {
  let #(origin, branch) = case agent_read_model.origin(entry) {
    agent_read_model.Bootstrap -> #("bootstrap", None)
    agent_read_model.Scratch -> #("scratch", None)
    agent_read_model.Branch(name) -> #("branch", Some(name))
  }
  "{\"name\":"
  <> mcp.json_string(agent_read_model.name(entry))
  <> ",\"kind\":"
  <> mcp.json_string(codebase_index.kind_of_entry(entry))
  <> ",\"ref\":"
  <> nullable_json_string(content_hex(cache, defs, entry))
  <> ",\"name_ref\":"
  <> mcp.json_string(codebase_index.ref_hex_entry(entry))
  <> ",\"origin\":"
  <> mcp.json_string(origin)
  <> ",\"branch\":"
  <> nullable_json_string(branch)
  <> "}"
}

pub fn nullable_json_string(value: Option(String)) -> String {
  case value {
    None -> "null"
    Some(ref) -> mcp.json_string(ref)
  }
}
