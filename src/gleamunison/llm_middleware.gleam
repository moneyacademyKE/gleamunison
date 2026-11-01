//// LLM handler middleware (gap analysis concept A, decomplected).
////
//// BAML complects retry/fallback/mocking into a client registry + hosted
//// studio. Here retry is plain handler composition: a middleware is just an
//// OpHandler wrapping another OpHandler. Same contract as llm.gleam:
//// continuation receives {ok, CompletionJsonBin} | {error, ReasonBin}.
////
//// The budget/fallback/recording compositions that duplicated
//// llm.complete_env's inline settlement path were deleted (bk-baac):
//// complete_env is the one live admit → release → meter → report authority
//// (session_refresh and gleamunison_repl_ffi call it), and the shipped CLI
//// path is intentionally budget-free — retry only.

import gleam/dynamic.{type Dynamic}
import gleamunison/dynamic_ffi.{from_dynamic}
import gleamunison/effects.{type OpHandler}
import gleamunison/llm_controls
import gleamunison/time_ffi.{sleep}

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
  case from_dynamic(result) {
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
