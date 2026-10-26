//// Strict percent-decoding for one application route path segment.
//// Raw separators are rejected before decoding; decoded separators are not
//// reinterpreted as route structure.

import gleam/bit_array
import gleam/result
import gleam/string

pub fn segment(raw: String) -> Result(String, Nil) {
  case
    string.contains(raw, "/")
    || string.contains(raw, "\\")
    || string.contains(raw, "?")
  {
    True -> Error(Nil)
    False ->
      case decode(bit_array.from_string(raw), <<>>) {
        Error(_) -> Error(Nil)
        Ok(bytes) ->
          case bit_array.to_string(bytes) {
            Error(_) -> Error(Nil)
            Ok(name) ->
              case string.contains(name, "/") || string.contains(name, "\\") {
                True -> Error(Nil)
                False -> Ok(name)
              }
          }
      }
  }
}

fn decode(raw: BitArray, acc: BitArray) -> Result(BitArray, Nil) {
  case raw {
    <<37, high, low, rest:bytes>> -> {
      use byte <- result.try(hex_byte(high, low))
      case byte {
        0 -> Error(Nil)
        _ -> decode(rest, <<acc:bits, byte>>)
      }
    }
    <<37, _:bytes>> -> Error(Nil)
    <<byte, rest:bytes>> -> decode(rest, <<acc:bits, byte>>)
    <<>> -> Ok(acc)
    _ -> Error(Nil)
  }
}

fn hex_byte(high: Int, low: Int) -> Result(Int, Nil) {
  use high <- result.try(hex_digit(high))
  use low <- result.try(hex_digit(low))
  Ok(high * 16 + low)
}

fn hex_digit(value: Int) -> Result(Int, Nil) {
  case value {
    _ if value >= 48 && value <= 57 -> Ok(value - 48)
    _ if value >= 65 && value <= 70 -> Ok(value - 55)
    _ if value >= 97 && value <= 102 -> Ok(value - 87)
    _ -> Error(Nil)
  }
}
