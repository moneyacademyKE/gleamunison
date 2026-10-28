//// One settlement boundary for LLM budget bookkeeping.
////
//// Admission happens before the provider call; this module owns everything
//// after it. Both the ambient completion path and handler middleware release
//// the slot once, then record the same success/failure sequence. Backend
//// refusals are values, never assertions that crash a completed provider call.

import gleam/io
import gleam/result

@external(erlang, "gleamunison_llm_budget", "release")
fn ffi_release(provider: String) -> Result(Nil, Nil)

@external(erlang, "gleamunison_llm_budget", "spend")
fn ffi_spend(
  provider: String,
  tokens: Int,
  cost_micro_usd: Int,
) -> Result(Nil, Nil)

@external(erlang, "gleamunison_llm_budget", "report_success")
fn ffi_report_success(provider: String) -> Result(Nil, Nil)

@external(erlang, "gleamunison_llm_budget", "report_failure")
fn ffi_report_failure(provider: String) -> Result(Nil, Nil)

pub fn release(provider: String) -> Result(Nil, String) {
  ffi_release(provider) |> describe_error(provider, "release")
}

pub fn success(
  provider: String,
  tokens: Int,
  cost_micro_usd: Int,
) -> Result(Nil, String) {
  use Nil <- result.try(
    ffi_spend(provider, tokens, cost_micro_usd)
    |> describe_error(provider, "spend"),
  )
  ffi_report_success(provider) |> describe_error(provider, "report success")
}

pub fn failure(provider: String) -> Result(Nil, String) {
  ffi_report_failure(provider) |> describe_error(provider, "report failure")
}

/// Reporting for callers that already hold a result they must not discard.
/// A handler that returns a real completion cannot also return a bookkeeping
/// error, so the failure goes to stderr: visible, never a crash, never a
/// silently dropped value.
pub fn report(outcome: Result(Nil, String)) -> Nil {
  case outcome {
    Ok(Nil) -> Nil
    Error(message) -> io.println_error(message)
  }
}

fn describe_error(
  outcome: Result(Nil, Nil),
  provider: String,
  operation: String,
) -> Result(Nil, String) {
  result.map_error(outcome, fn(_) {
    "llm budget: could not " <> operation <> " for " <> provider
  })
}
