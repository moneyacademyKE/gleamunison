//// LLM handler middleware (gap analysis concept A, decomplected).
////
//// BAML complects retry/fallback/mocking into a client registry + hosted
//// studio. Here they are plain handler composition: a middleware is just an
//// OpHandler wrapping another OpHandler. Same contract as llm.gleam:
//// continuation receives {ok, CompletionJsonBin} | {error, ReasonBin}.

import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/result
import gleamunison/effects.{type OpHandler}
import gleamunison/json
import gleamunison/llm.{type Completion}
import gleamunison/llm_budget
import gleamunison/llm_controls

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn to_dynamic(val: a) -> Dynamic

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn as_result(d: Dynamic) -> Result(BitArray, BitArray)

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn as_bit_array(d: Dynamic) -> BitArray

@external(erlang, "timer", "sleep")
fn sleep(ms: Int) -> Nil

@external(erlang, "gleamunison_llm_budget", "admit")
fn budget_admit(provider: String, model: String) -> Result(Nil, String)

@external(erlang, "gleamunison_llm_budget", "release")
fn budget_release(provider: String) -> Result(Nil, Nil)

@external(erlang, "gleamunison_llm_budget", "spend")
fn budget_spend(
  provider: String,
  tokens: Int,
  cost_micro_usd: Int,
) -> Result(Nil, Nil)

@external(erlang, "gleamunison_llm_budget", "report_success")
fn budget_report_success(provider: String) -> Result(Nil, Nil)

@external(erlang, "gleamunison_llm_budget", "report_failure")
fn budget_report_failure(provider: String) -> Result(Nil, Nil)

/// Budget/circuit gate as handler composition. Admit before the call,
/// release the concurrency slot exactly once, then meter actuals and
/// report the outcome. Refusals return the typed refusal name as the
/// handler error; the inner handler never runs.
pub fn budget_handler(
  inner: OpHandler,
  provider: llm.Provider,
  model: String,
) -> OpHandler {
  let name = llm.provider_name(provider)
  fn(args: List(Dynamic), cont: fn(Dynamic) -> Dynamic) -> Dynamic {
    case budget_admit(name, model) {
      Error(refusal) -> cont(to_dynamic(Error(bit_array.from_string(refusal))))
      Ok(Nil) -> {
        let result = inner(args, fn(d) { d })
        let assert Ok(Nil) = budget_release(name)
        case as_result(result) {
          Ok(json_bin) -> {
            case meter_completion(provider, json_bin) {
              Ok(#(tokens, cost)) -> {
                let assert Ok(Nil) = budget_spend(name, tokens, cost)
                let assert Ok(Nil) = budget_report_success(name)
                Nil
              }
              // An unparseable completion cannot be metered; it still
              // counts as a failure for the circuit.
              Error(_) -> {
                let assert Ok(Nil) = budget_report_failure(name)
                Nil
              }
            }
            cont(result)
          }
          Error(_) -> {
            let assert Ok(Nil) = budget_report_failure(name)
            cont(result)
          }
        }
      }
    }
  }
}

fn meter_completion(
  provider: llm.Provider,
  json_bin: BitArray,
) -> Result(#(Int, Int), Nil) {
  case bit_array.to_string(json_bin) {
    Error(_) -> Error(Nil)
    Ok(text) ->
      // House shape first (mocks and fixtures), provider wire shape second.
      case parse_house_completion(json_bin) {
        Ok(c) -> Ok(metered(c))
        Error(_) ->
          case llm.parse_response(provider, 200, text) {
            Error(_) -> Error(Nil)
            Ok(c) -> Ok(metered(c))
          }
      }
  }
}

fn parse_house_completion(json_bin: BitArray) -> Result(Completion, Nil) {
  case json.decode(json_bin) {
    Error(_) -> Error(Nil)
    Ok(dyn) ->
      decode.run(dyn, llm.completion_decoder()) |> result.replace_error(Nil)
  }
}

fn metered(c: Completion) -> #(Int, Int) {
  let tokens = c.input_tokens + c.output_tokens
  #(tokens, llm_budget.cost_micro_usd(c.input_tokens, c.output_tokens, 0, 0))
}

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
