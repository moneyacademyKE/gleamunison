//// One settlement boundary: release the slot, then record the same
//// spend/report sequence for every caller.
////
//// These pin the property the old inline `let assert Ok(Nil)` bodies broke:
//// a bookkeeping problem is data the caller can see, never an assertion that
//// takes down a call whose completion already succeeded.

import gleam/string
import gleamunison/llm_settlement
import gleeunit/should

@external(erlang, "gleamunison_llm_budget", "reset")
fn budget_reset() -> Result(Nil, Nil)

@external(erlang, "gleamunison_llm_budget", "admit")
fn budget_admit(provider: String, model: String) -> Result(Nil, String)

@external(erlang, "gleamunison_ffi_test", "llm_budget_snapshot_json")
fn snapshot_json() -> String

pub fn settlement_meters_one_admitted_call_test() {
  let assert Ok(Nil) = budget_reset()
  let assert Ok(Nil) = budget_admit("settle-provider", "m")
  let assert Ok(Nil) = llm_settlement.release("settle-provider")
  let assert Ok(Nil) = llm_settlement.success("settle-provider", 12, 34)
  let snap = snapshot_json()
  string.contains(snap, "settle-provider") |> should.be_true
  string.contains(snap, "\"tokens\":12") |> should.be_true
}

pub fn settlement_records_failure_after_release_test() {
  let assert Ok(Nil) = budget_reset()
  let assert Ok(Nil) = budget_admit("settle-fail", "m")
  let assert Ok(Nil) = llm_settlement.release("settle-fail")
  let assert Ok(Nil) = llm_settlement.failure("settle-fail")
  snapshot_json() |> string.contains("settle-fail") |> should.be_true
}

pub fn report_never_crashes_on_a_failed_settlement_test() {
  // The middleware path holds a real completion it must not discard, so a
  // bookkeeping error is reported to stderr and the call still returns.
  llm_settlement.report(Ok(Nil)) |> should.equal(Nil)
  llm_settlement.report(Error("llm budget: could not spend for p"))
  |> should.equal(Nil)
}
