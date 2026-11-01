//// Retry is the only live middleware composition; the fallback and
//// recording-mock tests were deleted together with their dead src
//// compositions (bk-baac).

import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleamunison/dynamic_ffi.{from_dynamic, to_dynamic}
import gleamunison/effects.{type OpHandler}
import gleamunison/llm_middleware.{RetryPolicy}
import test_ffi.{pd_counter_get, pd_counter_inc}

const no_args = []

fn identity_cont(d: Dynamic) -> Dynamic {
  d
}

fn scripted_fail_then_ok(key: String, fail_times: Int) -> OpHandler {
  fn(_args, cont) {
    let n = pd_counter_inc(bit_array.from_string(key))
    case n <= fail_times {
      True -> cont(to_dynamic(Error(bit_array.from_string("boom"))))
      False -> cont(to_dynamic(Ok(bit_array.from_string("ok-payload"))))
    }
  }
}

fn always_fail(key: String) -> OpHandler {
  fn(_args, cont) {
    let _ = pd_counter_inc(bit_array.from_string(key))
    cont(to_dynamic(Error(bit_array.from_string("always fails"))))
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
  let assert Ok(payload) = from_dynamic(result)
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
  let assert Error(reason) = from_dynamic(result)
  let assert True = reason == bit_array.from_string("always fails")
  let assert True = pd_counter_get(bit_array.from_string(key)) == 2
}
