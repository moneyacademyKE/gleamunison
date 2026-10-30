//// Test-harness FFI, declared once.
////
//// These bind the test-support Erlang modules (`gleamunison_ffi_test`,
//// `gleamunison_trace`, `gleamunison_log`, `gleamunison_app_db`,
//// `gleamunison_runtime_sup`, `gleamunison_llm_budget`) plus
//// `erlang:unique_integer/0`.
////
//// Every one of them used to be re-declared in each test module that wanted
//// it, under whatever name that file felt like: the same keyed counter was
//// `pd_counter_inc` in two modules and `increment` in four, and the HTTP
//// helpers were `http_get` in one and `ffi_http_get` in another. Same Erlang
//// function, same signature, five different spellings. One declaration each
//// here, imported by name — the same rule src follows through `dynamic_ffi`,
//// `loader_ffi`, `time_ffi` and `json`.

import gleam/dynamic.{type Dynamic}

/// Keyed process-dictionary counter: increment and return the new value. Tests
/// use it to prove an operation happened exactly once.
@external(erlang, "gleamunison_ffi_test", "pd_counter_inc")
pub fn pd_counter_inc(key: BitArray) -> Int

/// Keyed process-dictionary counter: the current value, 0 when never set.
@external(erlang, "gleamunison_ffi_test", "pd_counter_get")
pub fn pd_counter_get(key: BitArray) -> Int

/// Run `check` with no active storage bound, then restore the previous binding.
@external(erlang, "gleamunison_ffi_test", "without_active_storage")
pub fn without_active_storage(check: fn() -> a) -> a

/// Run `work` and return a crash as `Error(reason)` instead of taking the test
/// process down with it.
@external(erlang, "gleamunison_ffi_test", "rescue")
pub fn rescue(work: fn() -> Dynamic) -> Result(Dynamic, String)

/// GET against a server the test started itself.
@external(erlang, "gleamunison_ffi_test", "http_get")
pub fn http_get(port: Int, path: String) -> Result(#(Int, String), String)

/// POST against a server the test started itself.
@external(erlang, "gleamunison_ffi_test", "http_post")
pub fn http_post(
  port: Int,
  path: String,
  body: String,
) -> Result(#(Int, String), String)

@external(erlang, "gleamunison_ffi_test", "start_http_server")
pub fn start_http_server(port: Int) -> Nil

@external(erlang, "gleamunison_ffi_test", "stop_http_server")
pub fn stop_http_server() -> Nil

/// The budget holder's state as JSON, for assertions about admission and spend.
@external(erlang, "gleamunison_ffi_test", "llm_budget_snapshot_json")
pub fn snapshot_json() -> String

/// Reset the budget holder between tests.
@external(erlang, "gleamunison_llm_budget", "reset")
pub fn budget_reset() -> Result(Nil, Nil)

/// Monotonic unique integer, for paths and names that must not collide across
/// tests running in the same node.
@external(erlang, "erlang", "unique_integer")
pub fn unique_integer() -> Int

/// Run `work` against the app database at `path`.
@external(erlang, "gleamunison_app_db", "with_path")
pub fn with_db_path(path: String, work: fn() -> a) -> a

@external(erlang, "gleamunison_runtime_sup", "stop_db")
pub fn stop_db() -> Dynamic

/// Append to the observability log table the way a request worker does.
@external(erlang, "gleamunison_log", "log_entry")
pub fn log_entry(
  level: String,
  message: String,
  keys: List(String),
  vals: List(String),
) -> Nil

@external(erlang, "gleamunison_log", "log_count")
pub fn log_count() -> Int

@external(erlang, "gleamunison_log", "clear_logs")
pub fn clear_logs() -> Nil

/// Drive the trace capture path with a synthetic request.
@external(erlang, "gleamunison_trace", "capture_request")
pub fn capture_request(
  method: String,
  path: String,
  headers: List(#(String, String)),
) -> Result(String, String)

@external(erlang, "gleamunison_trace", "trace_count")
pub fn trace_count() -> Int

@external(erlang, "gleamunison_trace", "clear_traces")
pub fn clear_traces() -> Nil
