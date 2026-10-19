import gleam/string
import gleamunison/mcp
import gleeunit/should

pub fn malformed_jsonrpc_requests_are_rejected_test() {
  let server = mcp.Server(name: "test", version: "1", tools: [])
  let assert mcp.Respond(missing) =
    mcp.handle_message(server, "{\"id\":1,\"method\":\"ping\"}")
  string.contains(missing, "-32600") |> should.be_true
  let assert mcp.Respond(wrong) =
    mcp.handle_message(
      server,
      "{\"jsonrpc\":\"1.0\",\"id\":1,\"method\":\"ping\"}",
    )
  string.contains(wrong, "-32600") |> should.be_true
  let assert mcp.Respond(bad_call) =
    mcp.handle_message(
      server,
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{}}",
    )
  string.contains(bad_call, "-32602") |> should.be_true
}

pub fn json_string_escapes_control_characters_test() {
  let escaped = mcp.json_string("quote\" slash\\ line\n")
  string.contains(escaped, "\\\"") |> should.be_true
  string.contains(escaped, "\\\\") |> should.be_true
  string.contains(escaped, "\\n") |> should.be_true
}
