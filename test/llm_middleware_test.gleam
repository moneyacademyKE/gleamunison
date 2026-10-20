import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/string
import gleamunison/effects.{type OpHandler}
import gleamunison/llm
import gleamunison/llm_middleware.{RetryPolicy}
import gleamunison/llm_types.{Completion}

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn cast(a: anything) -> Dynamic

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn uncast(a: Dynamic) -> anything

@external(erlang, "gleamunison_ffi_test", "pd_counter_inc")
fn pd_counter_inc(key: BitArray) -> Int

@external(erlang, "gleamunison_ffi_test", "pd_counter_get")
fn pd_counter_get(key: BitArray) -> Int

@external(erlang, "gleamunison_ffi_test", "pd_record")
fn pd_record(key: BitArray, value: BitArray) -> Nil

@external(erlang, "gleamunison_ffi_test", "pd_records")
fn pd_records(key: BitArray) -> List(BitArray)

const no_args = []

fn identity_cont(d: Dynamic) -> Dynamic {
  d
}

fn scripted_fail_then_ok(key: String, fail_times: Int) -> OpHandler {
  fn(_args, cont) {
    let n = pd_counter_inc(bit_array.from_string(key))
    case n <= fail_times {
      True -> cont(cast(Error(bit_array.from_string("boom"))))
      False -> cont(cast(Ok(bit_array.from_string("ok-payload"))))
    }
  }
}

fn always_fail(key: String) -> OpHandler {
  fn(_args, cont) {
    let _ = pd_counter_inc(bit_array.from_string(key))
    cont(cast(Error(bit_array.from_string("always fails"))))
  }
}

pub fn retry_succeeds_after_transient_failures_test() {
  let key = "retry_transient"
  let inner = scripted_fail_then_ok(key, 2)
  let handler =
    llm_middleware.retry_handler(
      inner,
      RetryPolicy(max_attempts: 3, base_delay_ms: 0),
    )
  let result = handler(no_args, identity_cont)
  let assert Ok(payload) = uncast(result)
  let assert True = payload == bit_array.from_string("ok-payload")
  let assert True = pd_counter_get(bit_array.from_string(key)) == 3
}

pub fn retry_exhausts_and_returns_last_error_test() {
  let key = "retry_exhaust"
  let inner = always_fail(key)
  let handler =
    llm_middleware.retry_handler(
      inner,
      RetryPolicy(max_attempts: 2, base_delay_ms: 0),
    )
  let result = handler(no_args, identity_cont)
  let assert Error(reason) = uncast(result)
  let assert True = reason == bit_array.from_string("always fails")
  let assert True = pd_counter_get(bit_array.from_string(key)) == 2
}

pub fn fallback_first_success_wins_test() {
  let fail_key = "fb_first_ok_fail"
  let good = llm.mock_handler(Completion("primary", "m", 1, 1))
  let bad = always_fail(fail_key)
  let handler = llm_middleware.fallback_handler([good, bad])
  let result = handler(no_args, identity_cont)
  let assert Ok(json_bin) = uncast(result)
  let assert Ok(text) = bit_array.to_string(json_bin)
  let assert True = string.contains(text, "\"content\":\"primary\"")
  // second provider never touched
  let assert True = pd_counter_get(bit_array.from_string(fail_key)) == 0
}

pub fn fallback_skips_failures_in_order_test() {
  let k1 = "fb_skip_1"
  let k2 = "fb_skip_2"
  let good = llm.mock_handler(Completion("tertiary", "m", 1, 1))
  let handler =
    llm_middleware.fallback_handler([always_fail(k1), always_fail(k2), good])
  let result = handler(no_args, identity_cont)
  let assert Ok(json_bin) = uncast(result)
  let assert Ok(text) = bit_array.to_string(json_bin)
  let assert True = string.contains(text, "\"content\":\"tertiary\"")
  let assert True = pd_counter_get(bit_array.from_string(k1)) == 1
  let assert True = pd_counter_get(bit_array.from_string(k2)) == 1
}

pub fn fallback_all_fail_returns_last_error_test() {
  let k = "fb_all_fail"
  let handler =
    llm_middleware.fallback_handler([always_fail(k), always_fail(k)])
  let result = handler(no_args, identity_cont)
  let assert Error(reason) = uncast(result)
  let assert True = reason == bit_array.from_string("always fails")
}

pub fn recording_mock_captures_args_test() {
  let key = "rec_mock"
  let recorder = fn(bin: BitArray) {
    pd_record(bit_array.from_string(key), bin)
  }
  let handler =
    llm_middleware.recording_mock(Completion("canned", "m", 1, 1), recorder)
  let messages =
    bit_array.from_string("[{\"role\":\"user\",\"content\":\"hi\"}]")
  let result = handler([cast(messages)], identity_cont)
  let assert Ok(_) = uncast(result)
  let assert [recorded] = pd_records(bit_array.from_string(key))
  let assert True = recorded == messages
}
