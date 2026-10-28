//// Canonical byte codecs for namespace snapshots and branch heads.
//// This module knows data and refs, not branch mutation or storage policy.

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleamunison/identity.{
  type DefinitionRef, parse_ref_hex, ref_hex as canonical_ref_hex,
}

pub fn ref_hex(ref: DefinitionRef) -> String {
  canonical_ref_hex(ref)
}

fn hex_ref(text: String) -> Result(DefinitionRef, Nil) {
  parse_ref_hex(text) |> result.replace_error(Nil)
}

fn b64(text: String) -> String {
  bit_array.base64_encode(bit_array.from_string(text), True)
}

fn unb64(text: String) -> Result(String, Nil) {
  use bits <- result.try(bit_array.base64_decode(text))
  bit_array.to_string(bits)
}

pub fn serialize_bindings(bindings: Dict(String, DefinitionRef)) -> BitArray {
  let lines =
    dict.to_list(bindings)
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    |> list.map(fn(pair) { b64(pair.0) <> ":" <> ref_hex(pair.1) })
  bit_array.from_string(string.join(["ns", "1", ..lines], "\n"))
}

pub fn parse_bindings(
  bytes: BitArray,
) -> Result(Dict(String, DefinitionRef), Nil) {
  use text <- result.try(bit_array.to_string(bytes))
  case string.split(text, "\n") {
    ["ns", "1", ..lines] -> {
      use pairs <- result.try(
        list.try_fold(lines, [], fn(acc, line) {
          case string.split(line, ":") {
            [name_b64, hex] -> {
              use name <- result.try(unb64(name_b64))
              use ref <- result.try(hex_ref(hex))
              Ok([#(name, ref), ..acc])
            }
            _ -> Error(Nil)
          }
        }),
      )
      Ok(dict.from_list(pairs))
    }
    _ -> Error(Nil)
  }
}

pub fn serialize_head(
  branch: String,
  seq: Int,
  ns_ref: DefinitionRef,
  prev: Option(DefinitionRef),
) -> BitArray {
  let prev_hex = case prev {
    Some(ref) -> ref_hex(ref)
    None -> "-"
  }
  bit_array.from_string(string.join(
    ["head", "1", b64(branch), int.to_string(seq), ref_hex(ns_ref), prev_hex],
    ":",
  ))
}

pub fn parse_head(
  bytes: BitArray,
) -> Result(#(String, Int, DefinitionRef, Option(DefinitionRef)), Nil) {
  use text <- result.try(bit_array.to_string(bytes))
  case string.split(text, ":") {
    ["head", "1", branch_b64, seq_text, ns_hex, prev_hex] -> {
      use branch <- result.try(unb64(branch_b64))
      use seq <- result.try(int.parse(seq_text) |> result.replace_error(Nil))
      use ns_ref <- result.try(hex_ref(ns_hex))
      use prev <- result.try(case prev_hex {
        "-" -> Ok(None)
        hex -> hex_ref(hex) |> result.map(Some)
      })
      Ok(#(branch, seq, ns_ref, prev))
    }
    _ -> Error(Nil)
  }
}
