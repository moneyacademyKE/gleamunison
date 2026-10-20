import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/option.{Some}
import gleam/string
import gleamunison/capability
import gleamunison/effects.{type HandlerFrame, type OpHandler, HandlerFrame}
import gleamunison/llm
import gleamunison/sandbox_policy
import gleeunit/should

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn to_dynamic(val: a) -> Dynamic

@external(erlang, "gleamunison_ffi", "from_dynamic")
fn unsafe_coerce(val: Dynamic) -> a

@external(erlang, "gleamunison_ffi_test", "rescue")
fn ffi_rescue(f: fn() -> Dynamic) -> Result(Dynamic, String)

fn ok_handler() -> OpHandler {
  fn(args: List(Dynamic), cont: fn(Dynamic) -> Dynamic) -> Dynamic {
    let args: List(String) = unsafe_coerce(to_dynamic(args))
    let head = case args {
      [x, ..] -> x
      _ -> ""
    }
    cont(to_dynamic("allowed:" <> head))
  }
}

fn llm_frame(handler: OpHandler) -> HandlerFrame {
  HandlerFrame(ability: llm.ability_ref(), ops: dict.from_list([#(0, handler)]))
}

fn policy_for(
  profile: sandbox_policy.ExecutionProfile,
) -> sandbox_policy.SandboxPolicy {
  let key = capability.frame_key(llm_frame(ok_handler()))
  case profile {
    sandbox_policy.Local -> sandbox_policy.local(capability.allow([key]))
    sandbox_policy.AuthenticatedRemote ->
      sandbox_policy.authenticated_remote(capability.allow([key]))
    sandbox_policy.UntrustedExecution ->
      sandbox_policy.untrusted(
        capability.allow([]),
        Some(
          sandbox_policy.ExternalExecutor(
            name: "test-executor",
            launcher: fn(_input, _budget) { Ok("external") },
          ),
        ),
      )
  }
}

pub fn scope_policy_preserves_deny_by_default_test() {
  let frame = llm_frame(ok_handler())
  let key = capability.frame_key(frame)
  let policy = policy_for(sandbox_policy.Local)
  let frames = capability.guard_frames(policy.abilities, [frame])
  capability.check(policy.abilities, frames) |> should.be_ok
  let assert [guarded] = frames
  let assert Ok(handler) = dict.get(guarded.ops, 0)
  unsafe_coerce(handler([to_dynamic("run")], fn(d) { d }))
  |> should.equal("allowed:run")
  key |> string.length |> should.equal(10)
}

pub fn untrusted_policy_denies_llm_capability_test() {
  let frame = llm_frame(ok_handler())
  let policy = policy_for(sandbox_policy.UntrustedExecution)
  let frames = capability.guard_frames(policy.abilities, [frame])
  capability.check(policy.abilities, frames) |> should.be_error
  let assert [guarded] = frames
  let assert Ok(handler) = dict.get(guarded.ops, 0)
  let result = ffi_rescue(fn() { handler([to_dynamic("no")], fn(d) { d }) })
  let assert Error(reason) = result
  string.contains(reason, "capability_denied") |> should.be_true
}

pub fn scoped_run_denies_ambient_authority_test() {
  let policy = policy_for(sandbox_policy.UntrustedExecution)
  let denied = capability.check(policy.abilities, [llm_frame(ok_handler())])
  let assert Error(keys) = denied
  sandbox_policy.capability_refusals(policy, keys)
  |> should.equal([
    "capability_denied:" <> capability.frame_key(llm_frame(ok_handler())),
  ])
}

pub fn admitted_untrusted_policy_carries_budget_test() {
  let executor =
    sandbox_policy.ExternalExecutor(
      name: "test-executor",
      launcher: fn(_input, _budget) { Ok("external") },
    )
  let policy = sandbox_policy.untrusted(capability.allow([]), Some(executor))
  let assert Ok(policy) = sandbox_policy.admit(policy)
  policy.budget.deadline_ms |> should.equal(30_000)
  policy.budget.max_processes |> should.equal(1024)
  policy.budget.max_concurrency |> should.equal(64)
}
