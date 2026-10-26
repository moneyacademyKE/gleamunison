import gleam/list
import gleam/string
import gleamunison/agent_publish
import gleamunison/app_route
import gleamunison/storage
import gleeunit/should
import simplifile

@external(erlang, "gleamunison_ffi_test", "set_env")
fn set_env(key: String, value: String) -> Nil

@external(erlang, "gleamunison_ffi_test", "unset_env")
fn unset_env(key: String) -> Nil

@external(erlang, "gleamunison_ffi_test", "without_active_storage")
fn without_active_storage(check: fn() -> a) -> a

pub fn admitted_name_and_content_ref_execute_with_json_values_test() {
  with_published_app(fn(adapter, greeting_ref, answer_ref) {
    let by_name =
      app_route.request(
        adapter,
        "factory",
        "route-greeting",
        "{\"args\":[\"Moe\"]}",
      )
    let by_ref =
      app_route.request(
        adapter,
        "factory",
        "ref/" <> greeting_ref,
        "{\"args\":[\"Moe\"]}",
      )
    let value =
      app_route.request(adapter, "factory", "route-answer", "{\"args\":[]}")

    assert_success(by_name, greeting_ref, "factory", "\"hello Moe\"")
    assert_success(by_ref, greeting_ref, "factory", "\"hello Moe\"")
    assert_success(value, answer_ref, "factory", "42")
  })
}

pub fn routes_only_expose_content_bound_on_the_selected_branch_test() {
  with_published_app(fn(adapter, greeting_ref, _) {
    let missing_name =
      app_route.request(
        adapter,
        "other",
        "route-greeting",
        "{\"args\":[\"Moe\"]}",
      )
    let unbound_ref =
      app_route.request(
        adapter,
        "other",
        "ref/" <> greeting_ref,
        "{\"args\":[\"Moe\"]}",
      )
    let scratch =
      app_route.request(adapter, "factory", "scratch-only", "{\"args\":[]}")

    assert_status(missing_name, 404, "not_found")
    assert_status(unbound_ref, 404, "not_found")
    assert_status(scratch, 404, "not_found")
  })
}

pub fn malformed_and_unbounded_requests_are_refused_test() {
  with_published_app(fn(adapter, _, _) {
    let invalid =
      app_route.request(adapter, "factory", "route-answer", "not-json")
    let extra =
      app_route.request(
        adapter,
        "factory",
        "route-answer",
        "{\"args\":[],\"branch\":\"other\"}",
      )
    let wrong_arity =
      app_route.request(adapter, "factory", "route-answer", "{\"args\":[1]}")
    let oversized =
      app_route.request(
        adapter,
        "factory",
        "route-answer",
        string.repeat("x", 65_537),
      )

    assert_status(invalid, 400, "invalid_request")
    assert_status(extra, 400, "invalid_request")
    assert_status(wrong_arity, 400, "invalid_arguments")
    assert_status(oversized, 413, "request_too_large")
  })
}

pub fn route_segments_and_argument_count_are_bounded_test() {
  with_published_app(fn(adapter, _, _) {
    let encoded_slash =
      app_route.request(adapter, "factory", "route%2fanswer", "{\"args\":[]}")
    let bad_escape =
      app_route.request(adapter, "factory", "route%zz", "{\"args\":[]}")
    let nul =
      app_route.request(adapter, "factory", "route%00answer", "{\"args\":[]}")
    let query =
      app_route.request(
        adapter,
        "factory",
        "route-answer?branch=other",
        "{\"args\":[]}",
      )
    let too_many =
      app_route.request(
        adapter,
        "factory",
        "route-answer",
        "{\"args\":[1,2,3,4,5,6,7,8,9]}",
      )

    assert_status(encoded_slash, 400, "invalid_route")
    assert_status(bad_escape, 400, "invalid_route")
    assert_status(nul, 400, "invalid_route")
    assert_status(query, 400, "invalid_route")
    assert_status(too_many, 400, "invalid_request")
  })
}

fn assert_success(
  response: app_route.Response,
  ref: String,
  branch: String,
  rendered_value: String,
) {
  let assert app_route.Response(200, body) = response
  string.contains(body, "\"ref\":\"" <> ref <> "\"") |> should.be_true
  string.contains(body, "\"branch\":\"" <> branch <> "\"") |> should.be_true
  string.contains(body, "\"value\":" <> rendered_value) |> should.be_true
}

fn assert_status(response: app_route.Response, status: Int, code: String) {
  let app_route.Response(actual, body) = response
  actual |> should.equal(status)
  string.contains(body, "\"error\":\"" <> code <> "\"") |> should.be_true
}

fn with_published_app(
  work: fn(storage.StorageAdapter, String, String) -> a,
) -> a {
  let root = "/tmp/gleamunison-app-route-test"
  let path = root <> "/store.dets"
  let _ = storage.dets_delete_file(path)
  let assert Ok(_) = simplifile.create_directory_all(root)
  set_env("GLEAMUNISON_EVIDENCE_SIGNING_KEY", "app-route-test-key")
  let result =
    without_active_storage(fn() {
      let assert Ok(adapter) = storage.dets(path)
      let source =
        "(define (route-greeting name) (string-concat \"hello \" name))\n"
        <> "(define test_route-greeting (do Test expect 1))\n"
        <> "(define route-answer 42)\n"
        <> "(define test_route-answer (do Test expect 1))\n"
      let assert Ok(publication) =
        agent_publish.publish_source(adapter, source, "factory", False, root)
      let assert Ok(greeting) =
        list.find(publication.definitions, fn(item) {
          item.name == "route-greeting"
        })
      let assert Ok(answer) =
        list.find(publication.definitions, fn(item) {
          item.name == "route-answer"
        })
      work(adapter, greeting.content_ref, answer.content_ref)
    })
  unset_env("GLEAMUNISON_EVIDENCE_SIGNING_KEY")
  let _ = storage.dets_delete_file(path)
  result
}
