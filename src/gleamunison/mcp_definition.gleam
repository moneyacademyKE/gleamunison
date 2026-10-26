//// Agent-facing definition identity: `ref` is the elaborated content hash;
//// `name_ref` is the distinct stable name handle used for dependencies.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
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
  name: String,
) -> Option(String) {
  case test_runner.elaborated_def_for(name, defs, cache) {
    Error(_) -> None
    Ok(definition) ->
      Some(
        identity.hash_to_debug_string(codebase.hash_of_definition(definition)),
      )
  }
}

pub fn defs_json(
  cache: TypeCache,
  defs: List(#(String, SurfaceDef)),
) -> String {
  let parts = list.map(defs, fn(pair) { json(cache, defs, pair.0, pair.1) })
  "[" <> string.join(parts, ",") <> "]"
}

pub fn json(
  cache: TypeCache,
  defs: List(#(String, SurfaceDef)),
  name: String,
  def: SurfaceDef,
) -> String {
  "{\"name\":"
  <> mcp.json_string(name)
  <> ",\"kind\":"
  <> mcp.json_string(codebase_index.kind_of(def))
  <> ",\"ref\":"
  <> nullable_json_string(content_hex(cache, defs, name))
  <> ",\"name_ref\":"
  <> mcp.json_string(codebase_index.ref_hex(name, def))
  <> "}"
}

pub fn nullable_json_string(value: Option(String)) -> String {
  case value {
    None -> "null"
    Some(ref) -> mcp.json_string(ref)
  }
}
