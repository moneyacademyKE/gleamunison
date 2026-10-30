//// The JSON boundary: one codec, one renderer, one escaper.
////
//// `encode`/`decode` are the binary codec (gleamunison_json). `term_to_json`
//// and `json_quote` are the string renderer that the CLI envelope and the HTTP
//// response envelope share — declared here once, because two envelopes that
//// disagree about how a value becomes JSON, or how a string is escaped, are
//// two contracts and not one.

import gleam/dynamic.{type Dynamic}

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
