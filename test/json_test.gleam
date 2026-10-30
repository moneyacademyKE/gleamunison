import gleam/bit_array
import gleam/dynamic/decode
import gleam/string
import gleamunison/json

pub fn decode_object_fields_test() {
  let assert Ok(dyn) =
    json.decode(bit_array.from_string("{\"a\":1,\"b\":\"x\"}"))
  let assert Ok(pair) =
    decode.run(dyn, {
      use a <- decode.field("a", decode.int)
      use b <- decode.field("b", decode.string)
      decode.success(#(a, b))
    })
  let assert True = pair == #(1, "x")
}

pub fn decode_nested_array_test() {
  let assert Ok(dyn) = json.decode(bit_array.from_string("{\"items\":[1,2,3]}"))
  let assert Ok(items) =
    decode.run(
      dyn,
      decode.field("items", decode.list(decode.int), decode.success),
    )
  let assert True = items == [1, 2, 3]
}

pub fn decode_invalid_json_returns_error_test() {
  let assert Error(_) = json.decode(bit_array.from_string("{\"unclosed\":"))
}

pub fn encode_string_list_test() {
  let assert Ok(bin) = json.encode(["a", "b"])
  let assert Ok(text) = bit_array.to_string(bin)
  let assert True = text == "[\"a\",\"b\"]"
}

pub fn encode_escapes_quotes_test() {
  let assert Ok(bin) = json.encode("say \"hi\"")
  let assert Ok(text) = bit_array.to_string(bin)
  let assert True = string.contains(text, "\\\"hi\\\"")
}

pub fn json_quote_roundtrips_control_characters_test() {
  // The single owner's contract: quote, backslash, CR, TAB, NUL and US —
  // everything a raw JSON string cannot carry — must survive the round trip.
  let nasty = "cr\r tab\t nul\u{0} us\u{1f} quote\" back\\"
  let quoted = json.json_quote(nasty)
  let assert Ok(dyn) = json.decode(bit_array.from_string(quoted))
  let assert Ok(back) = decode.run(dyn, decode.string)
  let assert True = back == nasty
}

pub fn encode_roundtrips_control_characters_test() {
  let nasty = "cr\r tab\t nul\u{0} us\u{1f} quote\" back\\"
  let assert Ok(bin) = json.encode(nasty)
  let assert Ok(dyn) = json.decode(bin)
  let assert Ok(back) = decode.run(dyn, decode.string)
  let assert True = back == nasty
}
