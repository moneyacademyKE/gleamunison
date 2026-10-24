import gleam/bit_array
import gleam/int
import gleam/string
import gleamunison/lsp
import gleeunit/should

fn frame(body: String) -> String {
  "Content-Length: "
  <> int.to_string(bit_array.byte_size(<<body:utf8>>))
  <> "\r\n\r\n"
  <> body
}

pub fn unicode_frame_uses_utf8_byte_count_test() {
  lsp.encode_frame("café🦀") |> should.equal("Content-Length: 9\r\n\r\ncafé🦀")
}

pub fn concatenated_unicode_frames_preserve_next_header_test() {
  let next = frame("next")
  lsp.decode_framed(frame("café🦀") <> next)
  |> should.equal(Ok(#("café🦀", next)))
}

pub fn declared_length_cannot_split_a_utf8_codepoint_test() {
  lsp.decode_framed("Content-Length: 1\r\n\r\né") |> should.be_error
}

pub fn duplicate_and_negative_lengths_are_rejected_test() {
  lsp.decode_framed("Content-Length: 1\r\nContent-Length: 2\r\n\r\nxx")
  |> should.be_error
  lsp.decode_framed("Content-Length: -1\r\n\r\nxx") |> should.be_error
}

pub fn frame_headers_and_body_lengths_are_bounded_test() {
  lsp.decode_framed(
    "X: " <> string.repeat("x", 8192) <> "\r\nContent-Length: 1\r\n\r\nx",
  )
  |> should.be_error
  lsp.decode_framed("Content-Length: 1048577\r\n\r\n") |> should.be_error
}

pub fn lower_case_header_and_empty_body_remain_valid_test() {
  lsp.decode_framed("content-length: 0\r\n\r\nnext")
  |> should.equal(Ok(#("", "next")))
}
