//// Structured output for `run --json`. One line, parseable by any client:
////
////   {"ref": "<sha256>", "value": <json>}
////   {"ref": "<sha256>", "module": "m_ab12cd34", "function": {"name": "$eval", "arity": 2}}
////
//// The envelope is the CLI's contract; term_to_json owns how a value becomes
//// JSON (native where the shape is unambiguous, tagged for constructors,
//// opaque where JSON has no honest representation).

import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/list
import gleamunison/json

/// A value definition's result.
pub fn value_json(ref_hex: String, term: Dynamic) -> String {
  "{\"ref\":"
  <> json.json_quote(ref_hex)
  <> ",\"value\":"
  <> json.term_to_json(term, 0)
  <> "}"
}

/// A function, reported without executing it: the module, its compiled entry
/// point, and the declared arity a caller must supply.
pub fn function_json(
  ref_hex: String,
  module: String,
  arity: Int,
  exports: List(#(String, Int)),
) -> String {
  let #(name, export_arity) = primary_export(exports)
  "{\"ref\":"
  <> json.json_quote(ref_hex)
  <> ",\"module\":"
  <> json.json_quote(module)
  <> ",\"function\":{\"name\":"
  <> json.json_quote(name)
  <> ",\"export_arity\":"
  <> int.to_string(export_arity)
  <> ",\"arity\":"
  <> int.to_string(arity)
  <> "}}"
}

/// The compiled entry point: every definition module exports exactly
/// `'$eval'/0` (see compile_definition). The list is checked rather than
/// assumed so a change to that shape surfaces here instead of at a call site.
fn primary_export(exports: List(#(String, Int))) -> #(String, Int) {
  case list.find(exports, fn(pair) { pair.0 == "$eval" }) {
    Ok(pair) -> pair
    Error(_) -> #("$eval", 0)
  }
}
