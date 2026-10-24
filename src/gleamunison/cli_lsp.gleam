//// Stdio pump: one bounded header block, one exact UTF-8 body, then replies.

import gleam/list
import gleam/result
import gleam/string
import gleamunison/lsp
import gleamunison/lsp_frame
import gleamunison/lsp_types

@external(erlang, "gleamunison_lsp_stdio", "init")
fn stdio_binary_mode() -> Nil

@external(erlang, "gleamunison_lsp_stdio", "read_headers")
fn read_headers(limit: Int) -> Result(String, Nil)

@external(erlang, "gleamunison_lsp_stdio", "read_body")
fn stdio_read_bytes(n: Int) -> Result(String, Nil)

@external(erlang, "gleamunison_lsp_stdio", "write")
fn stdio_write(s: String) -> Nil

pub fn command(_args: List(String)) -> Nil {
  stdio_binary_mode()
  serve(lsp_types.new_state())
}

fn serve(state: lsp_types.State) -> Nil {
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

/// EOF, malformed/oversized headers, invalid UTF-8 and short bodies stop the
/// stream. Guessing a new boundary after bad framing would consume body bytes
/// as headers and silently desynchronize the client.
fn read_message() -> Result(String, Nil) {
  use headers <- result.try(read_headers(lsp_frame.max_header_bytes))
  use length <- result.try(lsp_frame.content_length(headers))
  stdio_read_bytes(length)
}
