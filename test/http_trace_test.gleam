import gleam/string
import gleeunit/should
import test_ffi.{clear_traces, http_get, start_http_server, stop_http_server}

@external(erlang, "gleamunison_ffi_test", "clear_http_token")
fn clear_http_token() -> Nil

/// /api/traces has always promised a request log; until bk-64a4 the only
/// writer was test scaffolding, so production served an eternally empty
/// list. The request path now captures before routing, so even a 404 probe
/// must appear in the trace list.
pub fn http_requests_appear_in_traces_test() {
  clear_http_token()
  clear_traces()
  start_http_server(18_110)
  // A distinctive path no route serves: capture precedes both authorization
  // and routing, so the 404 itself must show up as a trace entry.
  let assert Ok(#(404, _)) = http_get(18_110, "/bk-64a4-probe")
  let assert Ok(#(200, traces)) = http_get(18_110, "/api/traces")
  stop_http_server()
  clear_traces()
  should.be_true(string.contains(traces, "/bk-64a4-probe"))
  // The trace entry records the method alongside the path.
  should.be_true(string.contains(traces, "GET"))
}
