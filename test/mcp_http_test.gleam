import gleam/bit_array
import gleam/dynamic/decode
import gleam/string
import gleamunison/cli_run
import gleamunison/identity
import gleamunison/json
import gleamunison/mcp_server
import gleamunison/mcp_write
import gleamunison/run_ref
import gleamunison/storage
import gleeunit/should
import simplifile

@external(erlang, "gleamunison_ffi_test", "start_http_server")
fn ffi_start_http_server(port: Int) -> Nil

@external(erlang, "gleamunison_ffi_test", "stop_http_server")
fn ffi_stop_http_server() -> Nil

@external(erlang, "gleamunison_ffi_test", "http_get")
fn ffi_http_get(port: Int, path: String) -> Result(#(Int, String), String)

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

@external(erlang, "gleamunison_ffi_test", "set_env")
fn ffi_set_env(key: String, value: String) -> Nil

@external(erlang, "gleamunison_ffi_test", "unset_env")
fn ffi_unset_env(key: String) -> Nil

@external(erlang, "gleamunison_ffi_test", "without_active_storage")
fn without_active_storage(check: fn() -> a) -> a

pub fn http_scratch_is_visible_to_mcp_and_browse_test() {
  let assert Ok(Nil) = mcp_server.start([])
  ffi_start_http_server(18_102)
  let assert Ok(#(200, _)) =
    ffi_http_get(18_102, "/define?name=factory_shared&expr=42")
  let call_body =
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"get_definition\",\"arguments\":{\"name\":\"factory_shared\"}}}"
  let mcp_response = ffi_http_post(18_102, "/mcp", call_body)
  let eval_body =
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"eval\",\"arguments\":{\"expr\":\"factory_shared\"}}}"
  let eval_response = ffi_http_post(18_102, "/mcp", eval_body)
  let browse_response = ffi_http_get(18_102, "/browse")

  mcp_server.stop()
  ffi_stop_http_server()

  let assert Ok(#(200, definition)) = mcp_response
  string.contains(definition, "factory_shared") |> should.be_true
  string.contains(definition, "\\\"origin\\\":\\\"scratch\\\"")
  |> should.be_true
  string.contains(definition, "\\\"ref\\\":")
  |> should.be_true
  let assert Ok(#(200, value)) = eval_response
  string.contains(value, "42 : Int") |> should.be_true
  let assert Ok(#(200, browse)) = browse_response
  string.contains(browse, "\"origin\":\"scratch\"") |> should.be_true
  string.contains(browse, "\"name_ref\":") |> should.be_true
}

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

pub fn mcp_authority_untrusted_execution_refuses_eval_test() {
  let assert Ok(Nil) = mcp_server.start([])
  ffi_set_env("GLEAMUNISON_PROFILE", "untrusted-execution")
  ffi_start_http_server(18_101)

  let call_body =
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"eval\",\"arguments\":{\"expr\":\"(add 20 22)\"}}}"
  let response = ffi_http_post(18_101, "/mcp", call_body)

  ffi_unset_env("GLEAMUNISON_PROFILE")
  mcp_server.stop()
  ffi_stop_http_server()

  let assert Ok(#(403, body)) = response
  let assert True = string.contains(body, "sandbox_refused")
  let assert True = string.contains(body, "missing_external_executor")
}

pub fn mcp_publish_refreshes_reads_preserves_scratch_and_runs_test() {
  let root = "/tmp/gleamunison-mcp-publish-test"
  let path = root <> "/store.dets"
  let _ = storage.dets_delete_file(path)
  let assert Ok(_) = simplifile.create_directory_all(root)
  ffi_set_env("GLEAMUNISON_STORE_DIR", root)
  ffi_set_env("GLEAMUNISON_BRANCH", "factory")
  ffi_set_env("GLEAMUNISON_EVIDENCE_SIGNING_KEY", "mcp-publish-test-key")

  let #(published, definition, scratch) =
    without_active_storage(fn() {
      let assert Ok(Nil) = mcp_server.start([])
      ffi_start_http_server(18_103)
      let assert Ok(#(200, _)) =
        ffi_http_get(18_103, "/define?name=mcp-scratch&expr=7")
      let publish_body =
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"agent_publish\",\"arguments\":{\"source\":\"(define mcp-published 42)\\n(define test_mcp-published (do Test expect 1))\\n\"}}}"
      let publish_response = ffi_http_post(18_103, "/mcp", publish_body)
      let definition_body =
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"get_definition\",\"arguments\":{\"name\":\"mcp-published\"}}}"
      let definition_response = ffi_http_post(18_103, "/mcp", definition_body)
      let scratch_body =
        "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"eval\",\"arguments\":{\"expr\":\"mcp-scratch\"}}}"
      let scratch_response = ffi_http_post(18_103, "/mcp", scratch_body)
      mcp_server.stop()
      ffi_stop_http_server()
      #(publish_response, definition_response, scratch_response)
    })

  ffi_unset_env("GLEAMUNISON_STORE_DIR")
  ffi_unset_env("GLEAMUNISON_BRANCH")
  ffi_unset_env("GLEAMUNISON_EVIDENCE_SIGNING_KEY")

  let assert Ok(#(200, publish_body)) = published
  let assert Ok(#(200, definition_body)) = definition
  let assert Ok(#(200, scratch_body)) = scratch
  let published_ref = publish_content_ref(publish_body)
  response_field(definition_body, "ref") |> should.equal(published_ref)
  string.contains(scratch_body, "7 : Int") |> should.be_true

  ffi_set_env("GLEAMUNISON_EVIDENCE_SIGNING_KEY", "mcp-publish-test-key")
  let assert Ok(adapter) = storage.dets(path)
  let assert Ok(ref) = identity.parse_ref_hex(published_ref)
  let execution =
    run_ref.run_verified_on_branch(adapter, ref, "factory", [], False)
  let assert Ok(Nil) = adapter.close()
  let cli_execution =
    cli_run.run([published_ref, "--store", path, "--branch", "factory"])
  ffi_unset_env("GLEAMUNISON_EVIDENCE_SIGNING_KEY")
  let _ = storage.dets_delete_file(path)
  execution |> should.equal(Ok("42"))
  cli_execution |> should.equal(Ok("42"))
}

pub fn mcp_untrusted_write_is_refused_before_storage_test() {
  let root = "/tmp/gleamunison-mcp-untrusted-write-test"
  let path = root <> "/store.dets"
  let _ = storage.dets_delete_file(path)
  ffi_set_env("GLEAMUNISON_STORE_DIR", root)
  ffi_set_env("GLEAMUNISON_PROFILE", "untrusted-execution")
  let result =
    without_active_storage(fn() {
      mcp_write.publish("(define must-not-exist 1)")
    })
  ffi_unset_env("GLEAMUNISON_STORE_DIR")
  ffi_unset_env("GLEAMUNISON_PROFILE")
  let assert Error(message) = result
  string.contains(message, "untrusted") |> should.be_true
  simplifile.is_file(path) |> should.equal(Ok(False))
}

fn publish_content_ref(response: String) -> String {
  let payload = tool_payload(response)
  let assert Ok(decoded) = json.decode(bit_array.from_string(payload))
  let decoder = {
    use definitions <- decode.field(
      "definitions",
      decode.list({
        use content_ref <- decode.field("content_ref", decode.string)
        decode.success(content_ref)
      }),
    )
    decode.success(definitions)
  }
  let assert Ok([content_ref]) = decode.run(decoded, decoder)
  content_ref
}

fn response_field(response: String, field: String) -> String {
  let payload = tool_payload(response)
  let assert Ok(decoded) = json.decode(bit_array.from_string(payload))
  let decoder = {
    use value <- decode.field(field, decode.string)
    decode.success(value)
  }
  let assert Ok(value) = decode.run(decoded, decoder)
  value
}

fn tool_payload(response: String) -> String {
  let text_decoder = {
    use text <- decode.field("text", decode.string)
    decode.success(text)
  }
  let result_decoder = {
    use items <- decode.field("content", decode.list(text_decoder))
    decode.success(items)
  }
  let envelope_decoder = {
    use texts <- decode.field("result", result_decoder)
    decode.success(texts)
  }
  let assert Ok(envelope) = json.decode(bit_array.from_string(response))
  let assert Ok([text]) = decode.run(envelope, envelope_decoder)
  text
}
