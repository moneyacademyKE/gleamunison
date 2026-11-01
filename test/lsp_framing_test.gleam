import gleam/string
import gleamunison/lsp
import gleamunison/lsp_frame
import gleeunit/should

pub fn unicode_frame_uses_utf8_byte_count_test() {
  lsp.encode_frame("café🦀") |> should.equal("Content-Length: 9\r\n\r\ncafé🦀")
}

// Wire splitting lives in the erl stdio pump (cli_lsp read_message →
// gleamunison_lsp_stdio; scripts/test_lsp_stdio.clj is its oracle). These
// cover the Gleam header-policy owner the pump calls: lsp_frame.

pub fn duplicate_and_negative_lengths_are_rejected_test() {
  lsp_frame.content_length("Content-Length: 1\r\nContent-Length: 2")
  |> should.be_error
  lsp_frame.content_length("Content-Length: -1") |> should.be_error
}

pub fn header_and_body_lengths_are_bounded_test() {
  lsp_frame.content_length(
    "X: " <> string.repeat("x", 8192) <> "\r\nContent-Length: 1",
  )
  |> should.be_error
  lsp_frame.content_length("Content-Length: 1048577") |> should.be_error
}

pub fn lower_case_header_and_zero_length_remain_valid_test() {
  lsp_frame.content_length("content-length: 0") |> should.equal(Ok(0))
}
