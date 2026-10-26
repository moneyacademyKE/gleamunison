//// Shared MCP tool argument and result codecs.

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import gleam/string
import gleamunison/mcp

pub fn names_json(names: List(String)) -> String {
  let parts = list.map(names, mcp.json_string)
  "[" <> string.join(parts, ",") <> "]"
}

pub fn string_arg(
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
