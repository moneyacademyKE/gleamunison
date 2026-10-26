//// Decode one bounded generation candidate through SAP and a closed envelope.
//// No source is evaluated or stored here; admission belongs to agent_publish.

import gleam/bit_array
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/result
import gleam/string
import gleamunison/sap

const max_source_bytes = 262_144

fn envelope_schema() -> sap.Schema {
  sap.SObj(
    fields: [#("source", sap.SText), #("signature", sap.SText)],
    required: ["source", "signature"],
  )
}

pub fn decode(
  raw: String,
  expected_signature: String,
) -> Result(String, String) {
  use value <- result.try(
    sap.decode_as(raw, envelope_schema()) |> result.map_error(describe_sap),
  )
  use fields <- result.try(decode_fields(value))
  use Nil <- result.try(case dict.size(fields) {
    2 -> Ok(Nil)
    _ -> Error("generation candidate must contain only source and signature")
  })
  use source <- result.try(string_field(fields, "source"))
  use signature <- result.try(string_field(fields, "signature"))
  use Nil <- result.try(case signature == expected_signature {
    True -> Ok(Nil)
    False -> Error("generation candidate signature does not match the prompt")
  })
  case string.trim(source) {
    "" -> Error("generation candidate source is empty")
    _ ->
      case
        bit_array.byte_size(bit_array.from_string(source)) <= max_source_bytes
      {
        True -> Ok(source)
        False -> Error("generation candidate source exceeds 262144 bytes")
      }
  }
}

fn decode_fields(value: Dynamic) -> Result(dict.Dict(String, Dynamic), String) {
  decode.run(value, decode.dict(decode.string, decode.dynamic))
  |> result.replace_error("generation candidate must be a JSON object")
}

fn string_field(
  fields: dict.Dict(String, Dynamic),
  name: String,
) -> Result(String, String) {
  use value <- result.try(
    dict.get(fields, name)
    |> result.replace_error("generation candidate is missing " <> name),
  )
  decode.run(value, decode.string)
  |> result.replace_error(
    "generation candidate " <> name <> " must be a string",
  )
}

fn describe_sap(error: sap.SapError) -> String {
  case error {
    sap.NoJsonFound -> "generation candidate contains no JSON"
    sap.StrictError(reason) ->
      "generation candidate is not valid JSON: " <> reason
    sap.ValidationFailed(paths) ->
      "generation candidate schema mismatch: " <> string.join(paths, ", ")
  }
}
