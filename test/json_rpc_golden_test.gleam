//// Golden bytes for the JSON-RPC envelope and id boundary (bk-3fe7).
////
//// Both RPC surfaces — MCP (mcp.gleam) and LSP (lsp_types.gleam) — render
//// through json.respond / json.error_respond / json.id_text /
//// json.id_of_dynamic. These pin the exact wire bytes the two hand-rolled
//// renderers produced before the fold, so the unification cannot drift.

import gleamunison/dynamic_ffi.{to_dynamic}
import gleamunison/json.{IntId, NoId, StrId}
import gleamunison/lsp_types
import gleamunison/mcp.{NoReply, Respond}
import gleeunit/should

fn server() -> mcp.Server {
  mcp.Server(name: "golden", version: "0.0.1", tools: [])
}

pub fn json_id_text_renders_each_shape_test() {
  json.id_text(IntId(7)) |> should.equal("7")
  json.id_text(StrId("req-1")) |> should.equal("\"req-1\"")
  json.id_text(NoId) |> should.equal("null")
}

pub fn json_id_of_dynamic_renders_each_shape_test() {
  json.id_of_dynamic(to_dynamic(3)) |> should.equal("3")
  json.id_of_dynamic(to_dynamic("req-2")) |> should.equal("\"req-2\"")
  json.id_of_dynamic(to_dynamic(Nil)) |> should.equal("null")
}

pub fn json_envelopes_are_byte_exact_test() {
  json.respond("7", "\"ok\"")
  |> should.equal("{\"jsonrpc\":\"2.0\",\"id\":7,\"result\":\"ok\"}")
  json.error_respond("null", -32_700, "Parse error")
  |> should.equal(
    "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32700,\"message\":\"Parse error\"}}",
  )
}

pub fn mcp_golden_bytes_test() {
  let assert Respond(int_id) =
    mcp.handle_message(
      server(),
      "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"ping\"}",
    )
  int_id
  |> should.equal("{\"jsonrpc\":\"2.0\",\"id\":7,\"result\":{}}")

  let assert Respond(string_id) =
    mcp.handle_message(
      server(),
      "{\"jsonrpc\":\"2.0\",\"id\":\"req-9\",\"method\":\"ping\"}",
    )
  string_id
  |> should.equal("{\"jsonrpc\":\"2.0\",\"id\":\"req-9\",\"result\":{}}")

  let assert NoReply =
    mcp.handle_message(
      server(),
      "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}",
    )

  let assert Respond(parse_error) = mcp.handle_message(server(), "{not json")
  parse_error
  |> should.equal(
    "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32700,\"message\":\"Parse error\"}}",
  )

  let assert Respond(not_found) =
    mcp.handle_message(
      server(),
      "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"frobnicate\"}",
    )
  not_found
  |> should.equal(
    "{\"jsonrpc\":\"2.0\",\"id\":6,\"error\":{\"code\":-32601,\"message\":\"Method not found\"}}",
  )
}

pub fn lsp_golden_bytes_test() {
  lsp_types.respond(to_dynamic(2), "null")
  |> should.equal("{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":null}")
  lsp_types.respond(to_dynamic("open-1"), "[]")
  |> should.equal("{\"jsonrpc\":\"2.0\",\"id\":\"open-1\",\"result\":[]}")
  lsp_types.error_response(to_dynamic(9), -32_601, "Method not found")
  |> should.equal(
    "{\"jsonrpc\":\"2.0\",\"id\":9,\"error\":{\"code\":-32601,\"message\":\"Method not found\"}}",
  )
}
