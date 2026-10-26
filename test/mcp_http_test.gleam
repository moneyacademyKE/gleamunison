import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/string
import gleamunison/cli_run
import gleamunison/evidence
import gleamunison/identity
import gleamunison/json
import gleamunison/mcp_generation
import gleamunison/mcp_server
import gleamunison/mcp_write
import gleamunison/publication
import gleamunison/run_ref
import gleamunison/source_loader
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

@external(erlang, "gleamunison_app_db", "with_path")
fn with_db_path(path: String, work: fn() -> a) -> a

@external(erlang, "gleamunison_runtime_sup", "stop_db")
fn stop_db() -> Dynamic

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

pub fn mcp_generation_reaches_configured_provider_and_app_test() {
  let root = "/tmp/gleamunison-mcp-generation-test"
  let path = root <> "/store.dets"
  let _ = storage.dets_delete_file(path)
  let assert Ok(_) = simplifile.create_directory_all(root)
  let candidate =
    "```json\n{source: '(define generated-number 42)\\n(define test_generated-number (do Test expect 1))', signature: 'int',}\n```"
  let assert Ok(provider_port) = start_completion_server(candidate)
  ffi_set_env("GLEAMUNISON_STORE_DIR", root)
  ffi_set_env("GLEAMUNISON_BRANCH", "factory")
  ffi_set_env("GLEAMUNISON_EVIDENCE_SIGNING_KEY", "mcp-generation-test-key")
  ffi_set_env("OPENAI_API_KEY", "local-test-only")
  ffi_set_env(
    "OPENAI_BASE_URL",
    "http://127.0.0.1:" <> int.to_string(provider_port) <> "/v1",
  )
  ffi_set_env("OPENAI_MODEL", "local-test")
  ffi_set_env("LLM_HTTP_TIMEOUT_MS", "5000")
  let result =
    without_active_storage(fn() {
      let assert Ok(Nil) = mcp_server.start([])
      ffi_start_http_server(18_104)
      let body =
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"agent_generate\",\"arguments\":{\"template\":\"Create a numeric answer with schema {{signature}}\",\"signature\":\"int\",\"max_attempts\":1}}}"
      let generated = ffi_http_post(18_104, "/mcp", body)
      let app = ffi_http_post(18_104, "/app/generated-number", "{\"args\":[]}")
      mcp_server.stop()
      ffi_stop_http_server()
      #(generated, app)
    })
  unset_generation_env()
  let #(generated, app) = result
  let assert Ok(#(200, generated_body)) = generated
  string.contains(generated_body, "\\\"attempts\\\":1") |> should.be_true
  let generated_ref = generation_content_ref(generated_body)
  string.length(generated_ref) |> should.equal(64)
  let assert Ok(#(200, app_body)) = app
  string.contains(app_body, "42") |> should.be_true
  ffi_set_env("GLEAMUNISON_EVIDENCE_SIGNING_KEY", "mcp-generation-test-key")
  let assert Ok(adapter) = storage.dets(path)
  let assert Ok(ref) = identity.parse_ref_hex(generated_ref)
  run_ref.run_verified_on_branch(adapter, ref, "factory", [], False)
  |> should.equal(Ok("42"))
  let assert Ok(Nil) = adapter.close()
  ffi_unset_env("GLEAMUNISON_EVIDENCE_SIGNING_KEY")
  let _ = storage.dets_delete_file(path)
}

@external(erlang, "gleamunison_generation_test", "start_completion_server")
fn start_completion_server(content: String) -> Result(Int, String)

fn unset_generation_env() -> Nil {
  ffi_unset_env("GLEAMUNISON_STORE_DIR")
  ffi_unset_env("GLEAMUNISON_BRANCH")
  ffi_unset_env("GLEAMUNISON_EVIDENCE_SIGNING_KEY")
  ffi_unset_env("OPENAI_API_KEY")
  ffi_unset_env("OPENAI_BASE_URL")
  ffi_unset_env("OPENAI_MODEL")
  ffi_unset_env("LLM_HTTP_TIMEOUT_MS")
}

pub fn mcp_generated_db_routes_survive_db_owner_restart_test() {
  let root = "/tmp/gleamunison-mcp-generated-db-test"
  let path = root <> "/store.dets"
  let db_path = root <> "/application.dets"
  let _ = storage.dets_delete_file(path)
  let _ = simplifile.delete(db_path)
  let assert Ok(_) = simplifile.create_directory_all(root)
  ffi_set_env("GLEAMUNISON_STORE_DIR", root)
  ffi_set_env("GLEAMUNISON_BRANCH", "factory")
  ffi_set_env("GLEAMUNISON_EVIDENCE_SIGNING_KEY", "generated-db-test-key")
  ffi_set_env("OPENAI_API_KEY", "local-test-only")
  ffi_set_env("OPENAI_MODEL", "local-test")
  ffi_set_env("LLM_HTTP_TIMEOUT_MS", "5000")
  let write =
    "(define generated-db-write (do Db transact (list (pair \"person:1\" (pair \"name\" \"Moe\"))) (list)))"
  let read = "(define generated-db-read (do Db get \"person:1\" \"name\"))"
  let #(write_response, read_response) =
    with_db_path(db_path, fn() {
      without_active_storage(fn() {
        let assert Ok(adapter) = storage.dets(path)
        attest_io(adapter, "generated-db-write", write)
        attest_io(adapter, "generated-db-read", read)
        let assert Ok(Nil) = mcp_server.start([])
        ffi_start_http_server(18_106)
        generate_from_provider(1, write, "int")
        generate_from_provider(2, read, "list")
        let write_response =
          ffi_http_post(18_106, "/app/generated-db-write", "{\"args\":[]}")
        let _ = stop_db()
        let read_response =
          ffi_http_post(18_106, "/app/generated-db-read", "{\"args\":[]}")
        mcp_server.stop()
        ffi_stop_http_server()
        #(write_response, read_response)
      })
    })
  unset_generation_env()
  let _ = storage.dets_delete_file(path)
  let _ = simplifile.delete(db_path)
  let assert Ok(#(200, write_body)) = write_response
  string.contains(write_body, "\"value\":1") |> should.be_true
  let assert Ok(#(200, read_body)) = read_response
  string.contains(read_body, "person:1") |> should.be_true
  string.contains(read_body, "Moe") |> should.be_true
}

fn attest_io(
  adapter: storage.StorageAdapter,
  name: String,
  source: String,
) -> Nil {
  let assert Ok(loaded) = source_loader.load(source)
  let assert Ok([subject]) =
    publication.subjects([name], loaded.definitions, loaded.cache)
  let assert Ok(signer) = evidence.production_signer()
  let assert Ok(_) =
    evidence.attach_signed(
      adapter,
      signer,
      subject.content_ref,
      evidence.Io,
      "approved",
      "factory acceptance: generated durable Db route",
      1,
    )
  Nil
}

fn generate_from_provider(id: Int, source: String, signature: String) -> Nil {
  let candidate =
    "{\"source\":"
    <> json_string(source)
    <> ",\"signature\":\""
    <> signature
    <> "\"}"
  let assert Ok(provider_port) = start_completion_server(candidate)
  ffi_set_env(
    "OPENAI_BASE_URL",
    "http://127.0.0.1:" <> int.to_string(provider_port) <> "/v1",
  )
  let body =
    "{\"jsonrpc\":\"2.0\",\"id\":"
    <> int.to_string(id)
    <> ",\"method\":\"tools/call\",\"params\":{\"name\":\"agent_generate\",\"arguments\":{\"template\":\"Generate the durable application route with {{signature}}\",\"signature\":\""
    <> signature
    <> "\",\"max_attempts\":1}}}"
  let result = ffi_http_post(18_106, "/mcp", body)
  let assert Ok(#(200, response)) = result
  let assert True = string.contains(response, "\\\"admitted\\\":1")
  Nil
}

@external(erlang, "gleamunison_ffi", "json_quote")
fn json_string(value: String) -> String

pub fn mcp_generation_rejects_untrusted_before_storage_test() {
  let root = "/tmp/gleamunison-mcp-untrusted-generation-test"
  let path = root <> "/store.dets"
  let _ = storage.dets_delete_file(path)
  ffi_set_env("GLEAMUNISON_STORE_DIR", root)
  ffi_set_env("GLEAMUNISON_PROFILE", "untrusted-execution")
  ffi_set_env("GLEAMUNISON_BRANCH", "factory")
  let assert Ok(decoded) =
    json.decode(bit_array.from_string(
      "{\"template\":\"generate\",\"signature\":\"int\",\"max_attempts\":1}",
    ))
  let assert Ok(args) =
    decode.run(decoded, decode.dict(decode.string, decode.dynamic))
  let result = without_active_storage(fn() { mcp_generation.generate(args) })
  ffi_unset_env("GLEAMUNISON_STORE_DIR")
  ffi_unset_env("GLEAMUNISON_PROFILE")
  ffi_unset_env("GLEAMUNISON_BRANCH")
  let assert Error(message) = result
  string.contains(message, "untrusted") |> should.be_true
  simplifile.is_file(path) |> should.equal(Ok(False))
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

fn generation_content_ref(response: String) -> String {
  let payload = tool_payload(response)
  let assert Ok(decoded) = json.decode(bit_array.from_string(payload))
  let decoder = {
    use definitions <- decode.field(
      "publication",
      decode.field(
        "definitions",
        decode.list({
          use content_ref <- decode.field("content_ref", decode.string)
          decode.success(content_ref)
        }),
        decode.success,
      ),
    )
    decode.success(definitions)
  }
  let assert Ok([content_ref]) = decode.run(decoded, decoder)
  content_ref
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
