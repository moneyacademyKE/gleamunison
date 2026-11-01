//// Shared LSP wire policy. Content-Length measures UTF-8 bytes.

import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

pub const max_header_bytes = 8192

pub const max_body_bytes = 1_048_576

pub fn content_length(headers: String) -> Result(Int, Nil) {
  use _ <- result.try(
    case bit_array.byte_size(<<headers:utf8>>) <= max_header_bytes {
      True -> Ok(Nil)
      False -> Error(Nil)
    },
  )
  use found <- result.try(
    list.try_fold(string.split(headers, "\r\n"), None, fn(found, line) {
      case string.split_once(line, ":") {
        Ok(#(name, value)) ->
          case string.lowercase(string.trim(name)) {
            "content-length" ->
              case found {
                Some(_) -> Error(Nil)
                None -> {
                  use length <- result.try(int.parse(string.trim(value)))
                  case length >= 0 && length <= max_body_bytes {
                    True -> Ok(Some(length))
                    False -> Error(Nil)
                  }
                }
              }
            _ -> Ok(found)
          }
        Error(_) -> Error(Nil)
      }
    }),
  )
  case found {
    Some(length) -> Ok(length)
    None -> Error(Nil)
  }
}

pub fn encode(body: String) -> String {
  "Content-Length: "
  <> int.to_string(bit_array.byte_size(<<body:utf8>>))
  <> "\r\n\r\n"
  <> body
}
