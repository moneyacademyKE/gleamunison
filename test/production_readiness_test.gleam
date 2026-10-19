import gleam/bit_array
import gleam/dynamic/decode
import gleam/list
import gleam/result
import gleamunison/health
import gleamunison/json
import gleeunit/should

@external(erlang, "gleamunison_health_test", "readiness_fixture")
fn readiness_fixture(mode: Int) -> Bool

@external(erlang, "gleamunison_health_test", "http_fixture")
fn http_fixture(mode: Int, path: String) -> Result(#(Int, String), String)

fn parse_json(body: String, decoder: decode.Decoder(a)) -> Result(a, Nil) {
  use value <- result.try(
    json.decode(bit_array.from_string(body)) |> result.replace_error(Nil),
  )
  decode.run(value, decoder) |> result.replace_error(Nil)
}

pub fn a_loaded_module_is_not_storage_readiness_test() {
  readiness_fixture(0) |> should.be_false
}

pub fn an_open_store_is_ready_test() {
  readiness_fixture(1) |> should.be_true
}

pub fn a_closed_store_is_not_ready_test() {
  readiness_fixture(2) |> should.be_false
}

pub fn memory_limit_failure_is_not_ready_test() {
  readiness_fixture(3) |> should.be_false
}

pub fn invalid_memory_limit_fails_closed_test() {
  readiness_fixture(4) |> should.be_false
}

pub fn absent_required_services_are_not_ready_test() {
  readiness_fixture(5) |> should.be_false
}

pub fn unknown_required_service_fails_closed_test() {
  readiness_fixture(6) |> should.be_false
}

pub fn custom_health_check_api_still_works_test() {
  let assert health.Healthy(_) =
    health.run_checks([health.HealthCheck("passing", fn() { True }, "test")])
}

pub fn readiness_endpoint_fails_with_503_test() {
  let assert Ok(#(status, body)) = http_fixture(0, "/api/ready")
  status |> should.equal(503)
  parse_json(body, decode.at(["ready"], decode.bool)) |> should.equal(Ok(False))
}

pub fn health_endpoint_no_longer_returns_false_200_test() {
  let assert Ok(#(status, body)) = http_fixture(0, "/api/health")
  status |> should.equal(503)
  parse_json(body, decode.at(["ready"], decode.bool)) |> should.equal(Ok(False))
}

pub fn healthy_http_report_is_structured_test() {
  let assert Ok(#(status, body)) = http_fixture(1, "/api/ready")
  status |> should.equal(200)
  parse_json(body, decode.at(["ready"], decode.bool)) |> should.equal(Ok(True))
  parse_json(body, decode.at(["version"], decode.string)) |> should.be_ok
  parse_json(body, decode.at(["schema_version"], decode.int))
  |> should.equal(Ok(1))
  let assert Ok(names) =
    parse_json(
      body,
      decode.at(["checks"], decode.list(decode.at(["name"], decode.string))),
    )
  list.each(["storage", "memory", "version", "schema"], fn(name) {
    list.contains(names, name) |> should.be_true
  })
}

pub fn missing_required_listener_is_http_failure_test() {
  let assert Ok(#(status, _)) = http_fixture(5, "/api/ready")
  status |> should.equal(503)
}

pub fn all_required_services_can_be_ready_test() {
  let assert Ok(#(status, body)) = http_fixture(7, "/api/ready")
  status |> should.equal(200)
  parse_json(body, decode.at(["ready"], decode.bool)) |> should.equal(Ok(True))
}

pub fn stalled_real_mcp_session_has_a_bounded_failure_test() {
  let assert Ok(#(status, body)) = http_fixture(8, "/api/ready")
  status |> should.equal(503)
  let assert Ok(details) =
    parse_json(
      body,
      decode.at(["checks"], decode.list(decode.at(["detail"], decode.string))),
    )
  list.contains(details, "check_timeout") |> should.be_true
}

pub fn liveness_is_independent_of_readiness_test() {
  let assert Ok(#(status, _)) = http_fixture(0, "/api/live")
  status |> should.equal(200)
}
