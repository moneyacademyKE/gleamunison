//// `gleamunison lsp` — stdio pump for the LSP server. The protocol layer
//// (lsp.gleam) is pure; this module only moves bytes: read a framed
//// message, hand it over, write the framed replies. EOF or `exit` stops.

import gleam/int
import gleam/list
import gleam/string
import gleamunison/lsp

@external(erlang, "gleamunison_ffi", "stdio_binary_mode")
fn stdio_binary_mode() -> Nil

@external(erlang, "gleamunison_ffi", "stdio_read_line")
fn stdio_read_line() -> Result(String, Nil)

@external(erlang, "gleamunison_ffi", "stdio_read_chars")
fn stdio_read_chars(n: Int) -> Result(String, Nil)

@external(erlang, "gleamunison_ffi", "stdio_write")
fn stdio_write(s: String) -> Nil

pub fn command(_args: List(String)) -> Nil {
  stdio_binary_mode()
  serve(lsp.new_state())
}

fn serve(state: lsp.State) -> Nil {
  case read_message() {
    Error(_) -> Nil
    Ok(body) -> {
      let #(replies, next_state) = lsp.handle_message(body, state)
      list.each(replies, fn(r) { stdio_write(lsp.encode_frame(r)) })
      case string.contains(body, "\"method\":\"exit\"") {
        True -> Nil
        False -> serve(next_state)
      }
    }
  }
}

/// Read one Content-Length framed message from stdin. EOF anywhere is a
/// clean stop; a malformed header block is skipped line by line until a
/// parseable Content-Length appears (an LSP client that speaks garbage
/// should not kill the server).
fn read_message() -> Result(String, Nil) {
  case read_headers(0) {
    Error(_) -> Error(Nil)
    Ok(length) -> stdio_read_chars(length)
  }
}

fn read_headers(length: Int) -> Result(Int, Nil) {
  case stdio_read_line() {
    Error(_) -> Error(Nil)
    Ok(line) -> {
      let trimmed = string.trim(line)
      case trimmed {
        "" ->
          case length {
            0 -> Error(Nil)
            n -> Ok(n)
          }
        _ ->
          case string.lowercase(trimmed) {
            "content-length:" <> rest ->
              case int.parse(string.trim(rest)) {
                Ok(n) -> read_headers(n)
                Error(_) -> read_headers(length)
              }
            _ -> read_headers(length)
          }
      }
    }
  }
}
