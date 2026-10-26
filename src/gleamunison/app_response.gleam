//// JSON response mapping for admitted application routes.
//// Uses the same bounded, honest term renderer as `run --json`.

import gleam/bit_array
import gleam/dynamic.{type Dynamic}

const max_response_bytes = 1_048_576

@external(erlang, "gleamunison_ffi", "term_to_json")
fn term_to_json(term: Dynamic, depth: Int) -> String

@external(erlang, "gleamunison_ffi", "json_quote")
fn quoted(text: String) -> String

pub fn success(
  ref: String,
  branch: String,
  term: Dynamic,
) -> Result(String, String) {
  let body =
    "{\"ref\":"
    <> quoted(ref)
    <> ",\"branch\":"
    <> quoted(branch)
    <> ",\"value\":"
    <> term_to_json(term, 0)
    <> "}"
  case bit_array.byte_size(bit_array.from_string(body)) <= max_response_bytes {
    True -> Ok(body)
    False -> Error("response_too_large")
  }
}

pub fn failure(code: String, detail: String) -> String {
  "{\"error\":" <> quoted(code) <> ",\"detail\":" <> quoted(detail) <> "}"
}
