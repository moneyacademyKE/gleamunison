import gleam/string
import gleeunit/should

@external(erlang, "gleamunison_observability", "export_json")
fn export_json() -> String

@external(erlang, "gleamunison_ffi_test", "observability_probe")
fn observability_redaction_probe(mode: Int) -> Bool

@external(erlang, "gleamunison_ffi_test", "metrics_restart_probe")
fn metrics_restart_probe() -> Bool

@external(erlang, "gleamunison_ffi_test", "http_drain_probe")
fn http_drain_probe() -> Bool

@external(erlang, "gleamunison_readiness", "http_response")
fn readiness_http_response() -> #(Int, String)

@external(erlang, "gleamunison_trace", "capture_request")
fn capture_request(
  method: String,
  path: String,
  headers: List(#(String, String)),
) -> Result(String, String)

@external(erlang, "gleamunison_trace", "trace_count")
fn trace_count() -> Int

@external(erlang, "gleamunison_trace", "clear_traces")
fn clear_traces() -> Nil

@external(erlang, "gleamunison_log", "log_entry")
fn log_entry(
  level: String,
  message: String,
  keys: List(String),
  vals: List(String),
) -> Nil

@external(erlang, "gleamunison_log", "log_count")
fn log_count() -> Int

@external(erlang, "gleamunison_log", "clear_logs")
fn clear_logs() -> Nil

pub fn export_is_machine_readable_with_all_sections_test() {
  let json = export_json()
  string.contains(json, "\"metrics\"") |> should.be_true
  string.contains(json, "\"traces\"") |> should.be_true
  string.contains(json, "\"logs\"") |> should.be_true
  string.contains(json, "\"saturation\"") |> should.be_true
  string.contains(json, "\"readiness\"") |> should.be_true
  string.contains(json, "\"exported_at\"") |> should.be_true
}

pub fn export_and_traces_never_leak_credentials_test() {
  // Captures a request carrying a credential, then proves the secret value
  // appears nowhere: not in the stored trace, not in the export.
  observability_redaction_probe(2) |> should.be_true
}

pub fn export_reports_saturation_limits_test() {
  let json = export_json()
  string.contains(json, "\"http_worker_limit\":64") |> should.be_true
  string.contains(json, "\"mcp_request_limit\":64") |> should.be_true
  string.contains(json, "\"sse_client_limit\":32") |> should.be_true
  string.contains(json, "\"trace_entry_limit\":512") |> should.be_true
  string.contains(json, "\"log_entry_limit\":1024") |> should.be_true
}

pub fn trace_table_survives_being_deleted_test() {
  // Crash/restart at the harshest level: the table itself is gone.
  clear_traces()
  let assert Ok(_id) = capture_request("GET", "/after-crash", [])
  { trace_count() >= 1 } |> should.be_true
}

pub fn log_table_survives_being_deleted_test() {
  clear_logs()
  log_entry("info", "after-crash", [], [])
  { log_count() >= 1 } |> should.be_true
}

pub fn metrics_server_restarts_after_kill_test() {
  metrics_restart_probe() |> should.be_true
}

pub fn http_server_drains_gracefully_test() {
  http_drain_probe() |> should.be_true
}

pub fn readiness_reports_all_boundary_checks_test() {
  let #(_status, body) = readiness_http_response()
  string.contains(body, "\"storage\"") |> should.be_true
  string.contains(body, "\"supervisors\"") |> should.be_true
  string.contains(body, "\"queues\"") |> should.be_true
  string.contains(body, "\"codebase\"") |> should.be_true
  string.contains(body, "\"provider\"") |> should.be_true
  string.contains(body, "\"schema\"") |> should.be_true
  string.contains(body, "\"memory\"") |> should.be_true
}
