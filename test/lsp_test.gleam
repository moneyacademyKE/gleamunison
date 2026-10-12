import gleam/int
import gleam/string
import gleamunison/lsp
import gleeunit/should

pub fn decode_framed_message_test() {
  let body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}"
  let framed =
    "Content-Length: "
    <> int.to_string(string.length(body))
    <> "\r\n\r\n"
    <> body
  let assert Ok(#(msg, rest)) = lsp.decode_framed(framed)
  msg |> should.equal(body)
  rest |> should.equal("")
}

pub fn decode_incomplete_waits_test() {
  let partial = "Content-Length: 100\r\n\r\n{\"jsonrpc\":"
  lsp.decode_framed(partial) |> should.be_error
}

pub fn initialize_advertises_full_sync_test() {
  let body =
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}"
  let #(replies, _) = lsp.handle_message(body, lsp.new_state())
  let assert [resp] = replies
  string.contains(resp, "textDocumentSync") |> should.be_true
  string.contains(resp, "\"id\":1") |> should.be_true
}

pub fn did_open_with_error_publishes_diagnostic_test() {
  let source = "(define main (add 1 nope-var))"
  let body =
    "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///tmp/x.lisp\",\"text\":\""
    <> source
    <> "\"}}}"
  let #(replies, _) = lsp.handle_message(body, lsp.new_state())
  let assert [notif] = replies
  string.contains(notif, "textDocument/publishDiagnostics") |> should.be_true
  string.contains(notif, "nope-var") |> should.be_true
  // Span from elaboration: line 0-based for LSP, so line 1 col 15 → line 0, col 14
  string.contains(notif, "\"line\":0") |> should.be_true
}

pub fn did_open_clean_publishes_empty_diagnostics_test() {
  let source = "(define main (add 1 2))"
  let body =
    "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///tmp/x.lisp\",\"text\":\""
    <> source
    <> "\"}}}"
  let #(replies, _) = lsp.handle_message(body, lsp.new_state())
  let assert [notif] = replies
  string.contains(notif, "publishDiagnostics") |> should.be_true
  string.contains(notif, "\"diagnostics\":[]") |> should.be_true
}

pub fn did_change_uses_new_text_test() {
  let source = "(define main (mul broken 2))"
  let body =
    "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\",\"params\":{\"textDocument\":{\"uri\":\"file:///tmp/x.lisp\"},\"contentChanges\":[{\"text\":\""
    <> source
    <> "\"}]}}"
  let #(replies, _) = lsp.handle_message(body, lsp.new_state())
  let assert [notif] = replies
  string.contains(notif, "broken") |> should.be_true
}

pub fn parse_error_maps_to_diagnostic_test() {
  let source = "(define main (add 1"
  let body =
    "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///tmp/x.lisp\",\"text\":\""
    <> source
    <> "\"}}}"
  let #(replies, _) = lsp.handle_message(body, lsp.new_state())
  let assert [notif] = replies
  string.contains(notif, "publishDiagnostics") |> should.be_true
  string.contains(notif, "nclosed") |> should.be_true
}

pub fn shutdown_replies_result_and_exit_is_silent_test() {
  let shutdown =
    "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"shutdown\",\"params\":null}"
  let #(replies, _) = lsp.handle_message(shutdown, lsp.new_state())
  let assert [resp] = replies
  string.contains(resp, "\"id\":9") |> should.be_true
  string.contains(resp, "\"result\":null") |> should.be_true
  // exit is a notification: no reply
  lsp.handle_message(
    "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}",
    lsp.new_state(),
  ).0
  |> should.equal([])
}

pub fn encode_frame_has_content_length_test() {
  let frame = lsp.encode_frame("hello")
  string.starts_with(frame, "Content-Length: 5\r\n\r\n") |> should.be_true
  string.ends_with(frame, "hello") |> should.be_true
}

fn open_then(source: String, request: String) -> List(String) {
  // JSON strings cannot hold raw newlines — clients send \\n escapes.
  let escaped =
    source
    |> string.replace("\\", "\\\\")
    |> string.replace("\n", "\\n")
  let open =
    "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///t.lisp\",\"text\":\""
    <> escaped
    <> "\"}}}"
  let #(_, state) = lsp.handle_message(open, lsp.new_state())
  let #(replies, _) = lsp.handle_message(request, state)
  replies
}

pub fn hover_on_use_shows_inferred_type_test() {
  let source = "(define add2 (lam x (add x 2)))\n(define main (add2 1))"
  // line 1 is (define main (add2 1)); "add2" sits at col 14 (0-based)
  let req =
    "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file:///t.lisp\"},\"position\":{\"line\":1,\"character\":15}}}"
  let assert [resp] = open_then(source, req)
  string.contains(resp, "\"id\":7") |> should.be_true
  string.contains(resp, "add2") |> should.be_true
  string.contains(resp, "Int") |> should.be_true
}

pub fn goto_definition_finds_define_line_test() {
  let source = "(define add2 (lam x (add x 2)))\n(define main (add2 1))"
  let req =
    "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"file:///t.lisp\"},\"position\":{\"line\":1,\"character\":15}}}"
  let assert [resp] = open_then(source, req)
  string.contains(resp, "\"id\":8") |> should.be_true
  string.contains(resp, "file:///t.lisp") |> should.be_true
  string.contains(resp, "\"line\":0") |> should.be_true
}

pub fn completion_matches_file_and_bootstrap_names_test() {
  let source = "(define add2 (lam x (add x 2)))\n(define main (ad"
  let req =
    "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"textDocument/completion\",\"params\":{\"textDocument\":{\"uri\":\"file:///t.lisp\"},\"position\":{\"line\":1,\"character\":16}}}"
  let assert [resp] = open_then(source, req)
  string.contains(resp, "\"id\":9") |> should.be_true
  string.contains(resp, "\"label\":\"add2\"") |> should.be_true
  string.contains(resp, "\"label\":\"add\"") |> should.be_true
}

pub fn hover_on_unknown_position_returns_null_test() {
  let source = "(define main (add 1 2))"
  let req =
    "{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file:///t.lisp\"},\"position\":{\"line\":9,\"character\":9}}}"
  let assert [resp] = open_then(source, req)
  string.contains(resp, "\"id\":10") |> should.be_true
  string.contains(resp, "\"result\":null") |> should.be_true
}
