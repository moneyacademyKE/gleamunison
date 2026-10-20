import gleam/bit_array
import gleam/int
import gleam/list
import gleamunison/identity.{hash_bytes, hash_to_bytes}
import gleeunit/should

// list.range is gone from modern stdlib; a tiny recursive loop does the job.
fn each_n(n: Int, fun: fn(Int) -> Nil) -> Nil {
  each_from(1, n, fun)
}

fn each_from(i: Int, n: Int, fun: fn(Int) -> Nil) -> Nil {
  case i <= n {
    False -> Nil
    True -> {
      fun(i)
      each_from(i + 1, n, fun)
    }
  }
}

fn ref_bytes(name: String) -> BitArray {
  hash_to_bytes(hash_bytes(bit_array.from_string(name)))
}

@external(erlang, "gleamunison_trace", "capture_request")
fn capture_request(
  method: String,
  path: String,
  headers: List(#(String, String)),
) -> Result(String, String)

@external(erlang, "gleamunison_trace", "get_trace")
fn get_trace(
  id: String,
) -> Result(#(String, String, String, String, List(#(String, String))), String)

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

@external(erlang, "gleamunison_storage", "new")
fn ets_new() -> BitArray

@external(erlang, "gleamunison_storage", "insert")
fn ets_insert(tab: BitArray, ref: BitArray, bytes: BitArray) -> Result(Nil, Nil)

@external(erlang, "gleamunison_storage", "list_refs_bounded")
fn ets_list_refs_bounded(
  tab: BitArray,
  limit: Int,
) -> Result(List(BitArray), Nil)

@external(erlang, "gleamunison_storage", "dets_new")
fn dets_new(path: String) -> Result(BitArray, Nil)

@external(erlang, "gleamunison_storage", "dets_insert")
fn dets_insert(
  tab: BitArray,
  ref: BitArray,
  bytes: BitArray,
) -> Result(Nil, Nil)

@external(erlang, "gleamunison_storage", "dets_list_refs_bounded")
fn dets_list_refs_bounded(
  tab: BitArray,
  limit: Int,
) -> Result(List(BitArray), Nil)

@external(erlang, "gleamunison_storage", "dets_close")
fn dets_close(tab: BitArray) -> Result(Nil, Nil)

@external(erlang, "gleamunison_storage", "dets_delete_file")
fn dets_delete_file(path: String) -> Result(Nil, Nil)

@external(erlang, "erlang", "unique_integer")
fn unique_integer() -> Int

pub fn trace_table_is_bounded_and_evicts_oldest_test() {
  clear_traces()
  let assert Ok(first_id) = capture_request("GET", "/first", [])
  each_n(520, fn(i) {
    let path = "/fill-" <> int.to_string(i)
    let assert Ok(_) = capture_request("GET", path, [])
    Nil
  })
  // 521 captures into a 512-entry table: the cap holds exactly.
  trace_count() |> should.equal(512)
  // The oldest entry was evicted to make room.
  get_trace(first_id) |> should.be_error
}

pub fn trace_capture_redacts_credential_headers_test() {
  clear_traces()
  let assert Ok(id) =
    capture_request("GET", "/secret", [
      #("authorization", "Bearer live-token"),
      #("cookie", "session=abc123"),
      #("x-api-key", "api-key-value"),
      #("user-agent", "probe"),
    ])
  let assert Ok(#(_ts, _id, _method, _path, headers)) = get_trace(id)
  headers
  |> list.each(fn(pair) {
    let #(_name, value) = pair
    { value != "Bearer live-token" } |> should.be_true
    { value != "session=abc123" } |> should.be_true
    { value != "api-key-value" } |> should.be_true
  })
  list.contains(headers, #("authorization", "[redacted]")) |> should.be_true
  list.contains(headers, #("cookie", "[redacted]")) |> should.be_true
  list.contains(headers, #("x-api-key", "[redacted]")) |> should.be_true
  // Non-credential headers survive untouched.
  list.contains(headers, #("user-agent", "probe")) |> should.be_true
}

pub fn log_table_is_bounded_test() {
  clear_logs()
  each_n(1030, fn(i) {
    log_entry("info", "fill-" <> int.to_string(i), [], [])
    Nil
  })
  log_count() |> should.equal(1024)
}

pub fn bounded_ets_listing_caps_results_test() {
  let tab = ets_new()
  each_n(10, fn(i) {
    let assert Ok(Nil) =
      ets_insert(tab, ref_bytes("bounded-" <> int.to_string(i)), <<i>>)
    Nil
  })
  let assert Ok(refs) = ets_list_refs_bounded(tab, 3)
  list.length(refs) |> should.equal(3)
  let assert Ok(all) = ets_list_refs_bounded(tab, 100)
  list.length(all) |> should.equal(10)
}

pub fn bounded_dets_listing_caps_results_test() {
  let path =
    "/tmp/gleamunison-bounded-list-"
    <> int.to_string(unique_integer())
    <> ".dets"
  let assert Ok(tab) = dets_new(path)
  each_n(8, fn(i) {
    let assert Ok(Nil) =
      dets_insert(tab, ref_bytes("dets-bounded-" <> int.to_string(i)), <<i>>)
    Nil
  })
  let assert Ok(refs) = dets_list_refs_bounded(tab, 2)
  list.length(refs) |> should.equal(2)
  let assert Ok(Nil) = dets_close(tab)
  let assert Ok(Nil) = dets_delete_file(path)
}

pub fn metric_names_stay_bounded_test() {
  // A metric name longer than 128 bytes is refused at the API edge and
  // never recorded; proof lives in the Erlang probe which can inspect the
  // raw registry entries.
  metrics_name_bound_probe() |> should.be_true
}

@external(erlang, "gleamunison_ffi_test", "metrics_name_bound_probe")
fn metrics_name_bound_probe() -> Bool
