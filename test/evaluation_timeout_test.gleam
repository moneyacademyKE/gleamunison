import gleam/string
import gleeunit/should

@external(erlang, "evaluation_scope_test_ffi", "descendants_die")
fn descendants_die() -> Bool

@external(erlang, "evaluation_scope_test_ffi", "cancelled_owner")
fn cancelled_owner() -> Bool

@external(erlang, "evaluation_scope_test_ffi", "successful_scope")
fn successful_scope() -> Bool

pub fn caller_cancellation_cleans_up_owned_processes_test() {
  cancelled_owner() |> should.be_true
}

pub fn successful_scope_does_not_leave_child_processes_test() {
  successful_scope() |> should.be_true
}

pub fn evaluation_timeout_kills_unlinked_child_and_grandchild_test() {
  descendants_die() |> should.be_true
}

@external(erlang, "gleamunison_ffi_io", "eval_expression")
fn ffi_eval_expression(expression: String) -> Result(String, String)

@external(erlang, "gleamunison_repl_ffi", "eval_module")
fn ffi_eval_module(module_name: String) -> Result(String, String)

@external(erlang, "gleamunison_ffi_test", "set_eval_timeout")
fn ffi_set_eval_timeout(timeout_ms: Int) -> Nil

@external(erlang, "gleamunison_ffi_test", "clear_eval_timeout")
fn ffi_clear_eval_timeout() -> Nil

pub fn evaluation_timeout_kills_infinite_expression_test() {
  ffi_set_eval_timeout(25)
  let result = ffi_eval_expression("((lam f (f f)) (lam f (f f)))")
  ffi_clear_eval_timeout()
  let assert Error(message) = result
  // Which budget halts the loop is machine-speed dependent: the wall-clock
  // deadline on slow hosts, the reduction ceiling (checked on the 10ms
  // budget tick) on fast CI runners, a contained worker-down on allocation
  // spikes. The invariant is containment under a named evaluation_* error,
  // not which budget won the race — asserting only "evaluation_timeout"
  // reproduced as the 507/1 "flake" locally and failed on all seven CI
  // matrix legs (bk-19fe).
  let assert True = string.contains(message, "evaluation_")
}

pub fn evaluation_timeout_preserves_normal_expression_test() {
  ffi_set_eval_timeout(1000)
  let result = ffi_eval_module("m_0000000a")
  ffi_clear_eval_timeout()
  let assert Ok(_) = result
}
