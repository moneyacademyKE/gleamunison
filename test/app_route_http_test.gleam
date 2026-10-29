import envoy
import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import gleam/string
import gleamunison/agent_publish
import gleamunison/evidence
import gleamunison/json
import gleamunison/mcp_server
import gleamunison/publication
import gleamunison/source_loader
import gleamunison/storage
import gleeunit/should
import simplifile

@external(erlang, "gleamunison_ffi_test", "start_http_server")
fn start_http_server(port: Int) -> Nil

@external(erlang, "gleamunison_ffi_test", "stop_http_server")
fn stop_http_server() -> Nil

@external(erlang, "gleamunison_ffi_test", "http_get")
fn http_get(port: Int, path: String) -> Result(#(Int, String), String)

@external(erlang, "gleamunison_ffi_test", "http_post")
fn http_post(
  port: Int,
  path: String,
  body: String,
) -> Result(#(Int, String), String)

@external(erlang, "gleamunison_ffi_test", "without_active_storage")
fn without_active_storage(check: fn() -> a) -> a

@external(erlang, "gleamunison_app_db", "with_path")
fn with_db_path(path: String, work: fn() -> a) -> a

@external(erlang, "gleamunison_runtime_sup", "stop_db")
fn stop_db() -> Dynamic

pub fn mcp_publish_then_http_app_route_executes_same_content_test() {
  let root = "/tmp/gleamunison-app-http-test"
  let path = root <> "/store.dets"
  let _ = storage.dets_delete_file(path)
  let assert Ok(_) = simplifile.create_directory_all(root)
  envoy.set("GLEAMUNISON_STORE_DIR", root)
  envoy.set("GLEAMUNISON_BRANCH", "factory")
  envoy.set("GLEAMUNISON_EVIDENCE_SIGNING_KEY", "app-http-test-key")

  let #(ref, by_name, by_ref, scratch) =
    without_active_storage(fn() {
      let assert Ok(Nil) = mcp_server.start([])
      start_http_server(18_105)
      let assert Ok(#(200, _)) =
        http_get(18_105, "/define?name=app-http-scratch&expr=7")
      let publish =
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"agent_publish\",\"arguments\":{\"source\":\"(define (app-http-greeting name) (string-concat \\\"hello \\\" name))\\n(define test_app-http-greeting (do Test expect 1))\\n\"}}}"
      let assert Ok(#(200, publication)) = http_post(18_105, "/mcp", publish)
      let content_ref = publish_content_ref(publication)
      let name_response =
        http_post(18_105, "/app/app-http-greeting", "{\"args\":[\"Moe\"]}")
      let ref_response =
        http_post(18_105, "/app/ref/" <> content_ref, "{\"args\":[\"Moe\"]}")
      let scratch_response =
        http_post(18_105, "/app/app-http-scratch", "{\"args\":[]}")
      mcp_server.stop()
      stop_http_server()
      #(content_ref, name_response, ref_response, scratch_response)
    })

  envoy.unset("GLEAMUNISON_STORE_DIR")
  envoy.unset("GLEAMUNISON_BRANCH")
  envoy.unset("GLEAMUNISON_EVIDENCE_SIGNING_KEY")
  let _ = storage.dets_delete_file(path)

  assert_route_success(by_name, ref)
  assert_route_success(by_ref, ref)
  let assert Ok(#(404, scratch_body)) = scratch
  string.contains(scratch_body, "\"error\":\"not_found\"") |> should.be_true
}

pub fn untrusted_profile_refuses_app_execution_test() {
  envoy.set("GLEAMUNISON_PROFILE", "untrusted-execution")
  let response =
    without_active_storage(fn() {
      let assert Ok(Nil) = mcp_server.start([])
      start_http_server(18_106)
      let result = http_post(18_106, "/app/anything", "{\"args\":[]}")
      mcp_server.stop()
      stop_http_server()
      result
    })
  envoy.unset("GLEAMUNISON_PROFILE")

  let assert Ok(#(403, body)) = response
  string.contains(body, "sandbox_refused") |> should.be_true
  string.contains(body, "missing_external_executor") |> should.be_true
}

pub fn http_app_route_persists_db_facts_across_owner_restart_test() {
  let root = "/tmp/gleamunison-app-db-http-test"
  let path = root <> "/store.dets"
  let db_path = root <> "/application.dets"
  let _ = storage.dets_delete_file(path)
  let _ = simplifile.delete(db_path)
  let assert Ok(_) = simplifile.create_directory_all(root)
  envoy.set("GLEAMUNISON_STORE_DIR", root)
  envoy.set("GLEAMUNISON_BRANCH", "factory")
  envoy.set("GLEAMUNISON_EVIDENCE_SIGNING_KEY", "app-http-test-key")

  let #(written, read) =
    with_db_path(db_path, fn() {
      without_active_storage(fn() {
        let assert Ok(adapter) = storage.dets(path)
        let source =
          "(define app-db-write (do Db transact (list (pair \"person:1\" (pair \"name\" \"Moe\"))) (list)))\n"
          <> "(define app-db-read (do Db get \"person:1\" \"name\"))\n"
        let assert Ok(loaded) = source_loader.load(source)
        let assert Ok(subjects) =
          publication.subjects(
            ["app-db-write", "app-db-read"],
            loaded.definitions,
            loaded.cache,
          )
        let assert Ok(signer) = evidence.production_signer()
        list.each(subjects, fn(subject) {
          let assert Ok(_) =
            evidence.attach_signed(
              adapter,
              signer,
              subject.content_ref,
              evidence.Io,
              "approved",
              "route database exercise",
              1,
            )
        })
        let assert Ok(_) =
          agent_publish.publish_source(adapter, source, "factory", False, root)
        let assert Ok(Nil) = mcp_server.start([])
        start_http_server(18_107)
        let write_response =
          http_post(18_107, "/app/app-db-write", "{\"args\":[]}")
        let _ = stop_db()
        let read_response =
          http_post(18_107, "/app/app-db-read", "{\"args\":[]}")
        mcp_server.stop()
        stop_http_server()
        #(write_response, read_response)
      })
    })

  envoy.unset("GLEAMUNISON_STORE_DIR")
  envoy.unset("GLEAMUNISON_BRANCH")
  envoy.unset("GLEAMUNISON_EVIDENCE_SIGNING_KEY")
  let _ = storage.dets_delete_file(path)
  let _ = simplifile.delete(db_path)

  let assert Ok(#(200, write_body)) = written
  string.contains(write_body, "\"value\":1") |> should.be_true
  let assert Ok(#(200, read_body)) = read
  string.contains(read_body, "person:1") |> should.be_true
  string.contains(read_body, "Moe") |> should.be_true
}

fn assert_route_success(
  response: Result(#(Int, String), String),
  expected_ref: String,
) {
  let assert Ok(#(200, body)) = response
  string.contains(body, "\"ref\":\"" <> expected_ref <> "\"")
  |> should.be_true
  string.contains(body, "\"branch\":\"factory\"") |> should.be_true
  string.contains(body, "\"value\":\"hello Moe\"") |> should.be_true
}

fn publish_content_ref(response: String) -> String {
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
  let assert Ok(payload) = json.decode(bit_array.from_string(text))
  let definitions_decoder = {
    use definitions <- decode.field(
      "definitions",
      decode.list({
        use content_ref <- decode.field("content_ref", decode.string)
        decode.success(content_ref)
      }),
    )
    decode.success(definitions)
  }
  let assert Ok([content_ref]) = decode.run(payload, definitions_decoder)
  content_ref
}
