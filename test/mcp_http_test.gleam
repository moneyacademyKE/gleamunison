import gleam/string
import gleamunison/mcp_server

@external(erlang, "gleamunison_ffi_test", "start_http_server")
fn ffi_start_http_server(port: Int) -> Nil

@external(erlang, "gleamunison_ffi_test", "stop_http_server")
fn ffi_stop_http_server() -> Nil

@external(erlang, "gleamunison_ffi_test", "http_post")
fn ffi_http_post(
  port: Int,
  path: String,
  body: String,
) -> Result(#(Int, String), String)

@external(erlang, "gleamunison_ffi_test", "http_post_auth")
fn ffi_http_post_auth(
  port: Int,
  path: String,
  body: String,
  token: String,
) -> Result(#(Int, String), String)

@external(erlang, "gleamunison_ffi_test", "http_post_auth_length")
fn ffi_http_post_auth_length(
  port: Int,
  path: String,
  body: String,
  token: String,
  declared_length: Int,
) -> Result(#(Int, String), String)

@external(erlang, "gleamunison_ffi_test", "set_http_token")
fn ffi_set_http_token(token: String) -> Nil

@external(erlang, "gleamunison_ffi_test", "clear_http_token")
fn ffi_clear_http_token() -> Nil

pub fn mcp_http_end_to_end_test() {
  let assert Ok(Nil) = mcp_server.start([])
  ffi_start_http_server(18_099)

  let init_body =
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}"
  let assert Ok(#(200, resp)) = ffi_http_post(18_099, "/mcp", init_body)
  let assert True = string.contains(resp, "protocolVersion")
  let assert True = string.contains(resp, "gleamunison")

  let call_body =
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"eval\",\"arguments\":{\"expr\":\"(add 20 22)\"}}}"
  let assert Ok(#(200, resp2)) = ffi_http_post(18_099, "/mcp", call_body)
  let assert True = string.contains(resp2, "42")
  let assert True = string.contains(resp2, "\"isError\":false")

  let notif_body =
    "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}"
  let assert Ok(#(202, _)) = ffi_http_post(18_099, "/mcp", notif_body)

  let assert Ok(#(404, _)) = ffi_http_post(18_099, "/nope", "{}")

  mcp_server.stop()
  ffi_stop_http_server()
}

pub fn mcp_http_auth_and_limit_test() {
  let assert Ok(Nil) = mcp_server.start([])
  ffi_set_http_token("test-token")
  ffi_start_http_server(18_100)

  let init_body =
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}"
  let assert Ok(#(401, _)) = ffi_http_post(18_100, "/mcp", init_body)
  let assert Ok(#(401, _)) =
    ffi_http_post_auth(18_100, "/mcp", init_body, "wrong-token")
  let assert Ok(#(200, resp)) =
    ffi_http_post_auth(18_100, "/mcp", init_body, "test-token")
  let assert True = string.contains(resp, "protocolVersion")

  let assert Ok(#(413, _)) =
    ffi_http_post_auth_length(18_100, "/mcp", "", "test-token", 1_048_577)

  ffi_clear_http_token()
  mcp_server.stop()
  ffi_stop_http_server()
}
