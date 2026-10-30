//// JSON response mapping for admitted application routes.
//// Uses the same bounded, honest term renderer as `run --json`.

import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleamunison/json

const max_response_bytes = 1_048_576

pub fn success(
  ref: String,
  branch: String,
  term: Dynamic,
) -> Result(String, String) {
  let body =
    "{\"ref\":"
    <> json.json_quote(ref)
    <> ",\"branch\":"
    <> json.json_quote(branch)
    <> ",\"value\":"
    <> json.term_to_json(term, 0)
    <> "}"
  case bit_array.byte_size(bit_array.from_string(body)) <= max_response_bytes {
    True -> Ok(body)
    False -> Error("response_too_large")
  }
}

pub fn failure(code: String, detail: String) -> String {
  "{\"error\":"
  <> json.json_quote(code)
  <> ",\"detail\":"
  <> json.json_quote(detail)
  <> "}"
}
