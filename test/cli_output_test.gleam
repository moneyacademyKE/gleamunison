//// Structured output: one JSON line a client can parse. Native where the
//// shape is unambiguous, tagged for constructors, opaque where JSON has no
//// honest representation. The depth cap is the only thing standing between a
//// self-referential term and a hung CLI.

import gleam/string
import gleamunison/cli_output
import gleamunison/dynamic_ffi.{to_dynamic}
import gleamunison/json
import gleeunit/should

fn json(value: a) -> String {
  json.term_to_json(to_dynamic(value), 0)
}

pub fn an_integer_is_native_test() {
  json(42) |> should.equal("42")
  json(-7) |> should.equal("-7")
}

pub fn text_is_a_json_string_test() {
  json("hi") |> should.equal("\"hi\"")
}

pub fn text_is_escaped_test() {
  json("a\"b\\c\nd") |> should.equal("\"a\\\"b\\\\c\\nd\"")
}

pub fn booleans_and_nil_are_literals_test() {
  json(True) |> should.equal("true")
  json(False) |> should.equal("false")
}

pub fn a_list_is_an_array_test() {
  json([1, 2, 3]) |> should.equal("[1,2,3]")
}

pub fn an_atom_tagged_tuple_is_a_constructor_test() {
  // The runtime shape a language constructor takes: {tag, args...}.
  json(#(True, 1)) |> should.equal("{\"tag\":\"true\",\"data\":[1]}")
}

pub fn a_plain_tuple_is_named_as_one_test() {
  json(#(1, 2)) |> should.equal("{\"tuple\":[1,2]}")
}

pub fn a_function_is_opaque_rather_than_invented_test() {
  // The printable form of a fun embeds an address, so the assertion checks the
  // shape: opaque, with the fun's own rendering inside it.
  let text = json(fn(x) { x })
  text |> string.starts_with("{\"opaque\":\"#Fun<") |> should.be_true
  text |> string.ends_with(">\"}") |> should.be_true
}

pub fn the_depth_cap_truncates_test() {
  // Depth 17 is past the cap of 16: the encoder names the depth rather than
  // recursing, which is what stops a self-referential term.
  json.term_to_json(to_dynamic(1), 17)
  |> should.equal("{\"truncated\":17}")
}

pub fn the_depth_cap_does_not_fire_early_test() {
  json.term_to_json(to_dynamic(1), 16) |> should.equal("1")
}

pub fn the_envelope_carries_the_ref_and_the_value_test() {
  cli_output.value_json("abc123", to_dynamic(7))
  |> should.equal("{\"ref\":\"abc123\",\"value\":7}")
}

pub fn the_function_envelope_names_the_entry_point_test() {
  cli_output.function_json("abc123", "m_ab12", 2, [#("$eval", 0)])
  |> should.equal(
    "{\"ref\":\"abc123\",\"module\":\"m_ab12\",\"function\":"
    <> "{\"name\":\"$eval\",\"export_arity\":0,\"arity\":2}}",
  )
}

pub fn quote_escapes_for_the_envelope_test() {
  json.json_quote("a\"b") |> should.equal("\"a\\\"b\"")
}
