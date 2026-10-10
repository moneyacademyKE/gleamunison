import gleam/bit_array
import gleam/dynamic
import gleam/dynamic/decode
import gleam/string
import gleamunison/ast
import gleamunison/json
import gleamunison/sap.{SBool, SInt, SList, SObj, SText}

pub fn clean_json_passes_through_test() {
  let assert Ok(repaired) = sap.parse("{\"a\": 1, \"b\": [1, 2]}")
  let assert True = repaired == "{\"a\": 1, \"b\": [1, 2]}"
}

pub fn strips_markdown_fence_test() {
  let input = "```json\n{\"a\": 1}\n```"
  let assert Ok(repaired) = sap.parse(input)
  let assert True = repaired == "{\"a\": 1}"
}

pub fn strips_yapping_around_json_test() {
  let input =
    "Sure! Here is the data you asked for:\n{\"a\": 1}\nHope that helps!"
  let assert Ok(repaired) = sap.parse(input)
  let assert True = repaired == "{\"a\": 1}"
}

pub fn repairs_trailing_commas_test() {
  let input = "{\"a\": 1, \"b\": [1, 2,],}"
  let assert Ok(repaired) = sap.parse(input)
  let assert Ok(dyn) = json_decode(repaired)
  let assert True = contains_int(dyn, "a", 1)
}

pub fn repairs_single_quotes_test() {
  let input = "{'name': 'moe', 'tags': ['a', 'b']}"
  let assert Ok(repaired) = sap.parse(input)
  let assert True = repaired == "{\"name\": \"moe\", \"tags\": [\"a\", \"b\"]}"
}

pub fn single_quoted_string_with_double_quote_inside_test() {
  let input = "{'say': 'he yelled \"stop\"'}"
  let assert Ok(repaired) = sap.parse(input)
  let assert Ok(dyn) = json_decode(repaired)
  let assert True = contains_text(dyn, "say", "he yelled \"stop\"")
}

pub fn repairs_unquoted_keys_test() {
  let input = "{name: \"moe\", age: 42}"
  let assert Ok(repaired) = sap.parse(input)
  let assert Ok(dyn) = json_decode(repaired)
  let assert True = contains_text(dyn, "name", "moe")
}

pub fn strips_line_and_block_comments_test() {
  let input = "{\n// leading comment\n\"a\": 1, /* inline */ \"b\": 2\n}"
  let assert Ok(repaired) = sap.parse(input)
  let assert Ok(dyn) = json_decode(repaired)
  let assert True = contains_int(dyn, "b", 2)
}

pub fn python_literals_become_json_test() {
  let input = "{\"ok\": True, \"missing\": None, \"bad\": False}"
  let assert Ok(repaired) = sap.parse(input)
  let assert Ok(dyn) = json_decode(repaired)
  let assert True = contains_bool(dyn, "ok", True)
}

pub fn combined_mess_repair_test() {
  let input =
    "```json\nHere you go:\n{flag: True, // trailing\n 'items': [1, 2,],}\n```\nDone!"
  let assert Ok(repaired) = sap.parse(input)
  let assert Ok(dyn) = json_decode(repaired)
  let assert True = contains_bool(dyn, "flag", True)
}

pub fn no_json_anywhere_is_error_test() {
  let assert Error(_) = sap.parse("I cannot help with that request.")
}

pub fn unrecoverable_json_is_error_test() {
  let assert Error(_) = sap.parse("{\"a\": [1, 2}")
}

pub fn decode_as_validates_against_schema_test() {
  let schema =
    SObj(
      fields: [#("name", SText), #("age", SInt), #("tags", SList(SText))],
      required: ["name", "age"],
    )
  let assert Ok(_) = sap.decode_as("{\"name\": \"moe\", \"age\": 42}", schema)
}

pub fn decode_as_reports_missing_required_field_test() {
  let schema = SObj(fields: [#("name", SText)], required: ["name"])
  let assert Error(err) = sap.decode_as("{\"other\": 1}", schema)
  let assert sap.ValidationFailed(paths) = err
  let assert True = list_any(paths, fn(p) { string.contains(p, "name") })
}

pub fn decode_as_reports_wrong_type_with_path_test() {
  let schema = SObj(fields: [#("age", SInt)], required: ["age"])
  let assert Error(err) = sap.decode_as("{\"age\": \"old\"}", schema)
  let assert sap.ValidationFailed(paths) = err
  let assert True = list_any(paths, fn(p) { string.contains(p, "age") })
}

pub fn schema_from_core_type_maps_builtins_test() {
  let assert True = sap.schema_from_type(ast.Builtin(ast.IntType)) == SInt
  let assert True = sap.schema_from_type(ast.Builtin(ast.BoolType)) == SBool
  let assert True =
    sap.schema_from_type(ast.Builtin(ast.ListType)) == SList(sap.SAny)
}

fn json_decode(s: String) -> Result(dynamic.Dynamic, BitArray) {
  json.decode(bit_array.from_string(s))
}

fn contains_int(d: dynamic.Dynamic, field: String, expect: Int) -> Bool {
  case decode.run(d, decode.field(field, decode.int, decode.success)) {
    Ok(v) -> v == expect
    Error(_) -> False
  }
}

fn contains_text(d: dynamic.Dynamic, field: String, expect: String) -> Bool {
  case decode.run(d, decode.field(field, decode.string, decode.success)) {
    Ok(v) -> v == expect
    Error(_) -> False
  }
}

fn contains_bool(d: dynamic.Dynamic, field: String, expect: Bool) -> Bool {
  case decode.run(d, decode.field(field, decode.bool, decode.success)) {
    Ok(v) -> v == expect
    Error(_) -> False
  }
}

fn list_any(xs: List(String), f: fn(String) -> Bool) -> Bool {
  case xs {
    [] -> False
    [h, ..t] -> f(h) || list_any(t, f)
  }
}
