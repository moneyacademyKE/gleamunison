//// The JSON boundary: one codec, one renderer, one escaper.
////
//// `encode`/`decode` are the binary codec (gleamunison_json). `term_to_json`
//// and `json_quote` are the string renderer that the CLI envelope and the HTTP
//// response envelope share — declared here once, because two envelopes that
//// disagree about how a value becomes JSON, or how a string is escaped, are
//// two contracts and not one.

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int

@external(erlang, "gleamunison_json", "encode")
pub fn encode(term: a) -> Result(BitArray, BitArray)

@external(erlang, "gleamunison_json", "decode")
pub fn decode(bin: BitArray) -> Result(a, BitArray)

/// Render a runtime term as JSON: native where the shape is unambiguous,
/// tagged for constructors, opaque where JSON has no honest representation.
/// `depth` bounds the recursion.
@external(erlang, "gleamunison_ffi", "term_to_json")
pub fn term_to_json(term: Dynamic, depth: Int) -> String

/// JSON-escape a string. The FFI owns escaping (control characters, UTF-8), so
/// the envelope and the values it wraps agree on one encoder.
@external(erlang, "gleamunison_ffi", "json_quote")
pub fn json_quote(text: String) -> String

/// A JSON-RPC request id as data: an integer, a string, or absent.
/// Notifications arrive without an id and are never answered.
pub type JsonId {
  IntId(Int)
  StrId(String)
  NoId
}

/// Render a request id as JSON text: bare integer, quoted string, or null.
pub fn id_text(id: JsonId) -> String {
  case id {
    IntId(n) -> int.to_string(n)
    StrId(s) -> json_quote(s)
    NoId -> "null"
  }
}

/// Render the id carried by an LSP frame, whose decoded JSON value has no
/// static type: an integer renders bare, a string quoted, anything else
/// (absent, null, or malformed) renders null.
pub fn id_of_dynamic(id: Dynamic) -> String {
  case decode.run(id, decode.int) {
    Ok(n) -> int.to_string(n)
    Error(_) ->
      case decode.run(id, decode.string) {
        Ok(s) -> json_quote(s)
        Error(_) -> "null"
      }
  }
}

/// The JSON-RPC success envelope. The result is already JSON text.
pub fn respond(id_text: String, result: String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":" <> id_text <> ",\"result\":" <> result <> "}"
}

/// The JSON-RPC error envelope. The message is escaped here, once.
pub fn error_respond(id_text: String, code: Int, message: String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":"
  <> id_text
  <> ",\"error\":{\"code\":"
  <> int.to_string(code)
  <> ",\"message\":"
  <> json_quote(message)
  <> "}}"
}
