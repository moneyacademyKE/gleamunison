//// LLM handler middleware (gap analysis concept A, decomplected).
////
//// BAML complects retry/fallback/mocking into a client registry + hosted
//// studio. Here they are plain handler composition: a middleware is just an
//// OpHandler wrapping another OpHandler. Same contract as llm.gleam:
//// continuation receives {ok, CompletionJsonBin} | {error, ReasonBin}.

import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleamunison/effects.{type OpHandler}
import gleamunison/llm.{type Completion}
import gleamunison/llm_controls

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn to_dynamic(val: a) -> Dynamic

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn as_result(d: Dynamic) -> Result(BitArray, BitArray)

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn as_bit_array(d: Dynamic) -> BitArray

@external(erlang, "timer", "sleep")
fn sleep(ms: Int) -> Nil

pub type RetryPolicy {
  RetryPolicy(max_attempts: Int, base_delay_ms: Int)
}

/// At most three attempts with at most 1000ms delay per retry. Terminal
/// settings/auth/decode/cancellation errors must not repeat a keyed call.
pub fn retry_handler(inner: OpHandler, policy: RetryPolicy) -> OpHandler {
  fn(args: List(Dynamic), cont: fn(Dynamic) -> Dynamic) -> Dynamic {
    cont(attempt(inner, policy, args, 1))
  }
}

fn attempt(
  inner: OpHandler,
  policy: RetryPolicy,
  args: List(Dynamic),
  n: Int,
) -> Dynamic {
  let result = inner(args, fn(d) { d })
  case as_result(result) {
    Ok(_) -> result
    Error(reason) ->
      case
        n < llm_controls.attempts(policy.max_attempts)
        && llm_controls.retryable(reason)
      {
        False -> result
        True -> {
          sleep(llm_controls.retry_delay(policy.base_delay_ms, n))
          attempt(inner, policy, args, n + 1)
        }
      }
  }
}

/// Try handlers in order; the first {ok, _} wins. All failing returns the
/// last handler's error.
pub fn fallback_handler(handlers: List(OpHandler)) -> OpHandler {
  fn(args: List(Dynamic), cont: fn(Dynamic) -> Dynamic) -> Dynamic {
    cont(chain(handlers, args))
  }
}

fn chain(handlers: List(OpHandler), args: List(Dynamic)) -> Dynamic {
  case handlers {
    [] -> to_dynamic(Error(bit_array.from_string("fallback: no providers")))
    [handler, ..rest] -> {
      let result = handler(args, fn(d) { d })
      case as_result(result) {
        Ok(_) -> result
        Error(_) ->
          case rest {
            [] -> result
            _ -> chain(rest, args)
          }
      }
    }
  }
}

/// Deterministic mock that also reports the messages JSON it received —
/// the fixture recorder for the eval family (gap analysis concept E).
pub fn recording_mock(
  response: Completion,
  record: fn(BitArray) -> Nil,
) -> OpHandler {
  fn(args: List(Dynamic), cont: fn(Dynamic) -> Dynamic) -> Dynamic {
    case args {
      [messages_dyn, ..] -> record(as_bit_array(messages_dyn))
      [] -> Nil
    }
    cont(to_dynamic(Ok(llm.completion_json(response))))
  }
}
