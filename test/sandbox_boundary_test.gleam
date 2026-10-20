import gleam/option.{None, Some}
import gleamunison/capability
import gleamunison/sandbox_policy
import gleeunit/should

pub fn local_profile_preserves_trusted_execution_test() {
  let policy = sandbox_policy.local(capability.allow([]))
  sandbox_policy.admit(policy) |> should.equal(Ok(policy))
  policy.profile |> sandbox_policy.profile_name |> should.equal("local")
}

pub fn authenticated_remote_is_not_untrusted_sandbox_test() {
  let policy = sandbox_policy.authenticated_remote(capability.allow([]))
  sandbox_policy.admit(policy) |> should.equal(Ok(policy))
  policy.profile
  |> sandbox_policy.profile_name
  |> should.equal("authenticated-remote")
}

pub fn untrusted_requires_external_executor_test() {
  let policy = sandbox_policy.untrusted(capability.allow([]), None)
  let assert Error(refusal) = sandbox_policy.admit(policy)
  sandbox_policy.refusal_name(refusal)
  |> should.equal("missing_external_executor")
}

pub fn untrusted_denies_direct_host_ffi_test() {
  let policy =
    sandbox_policy.SandboxPolicy(
      profile: sandbox_policy.UntrustedExecution,
      budget: sandbox_policy.default_budget(),
      abilities: capability.allow([]),
      direct_host_ffi: True,
      native_jets: False,
      external_executor: Some(
        sandbox_policy.ExternalExecutor(
          name: "test",
          launcher: fn(_input, _budget) { Ok("external") },
        ),
      ),
    )
  let assert Error(refusal) = sandbox_policy.admit(policy)
  sandbox_policy.refusal_name(refusal) |> should.equal("direct_host_ffi_denied")
}

pub fn untrusted_denies_native_jets_test() {
  let policy =
    sandbox_policy.SandboxPolicy(
      profile: sandbox_policy.UntrustedExecution,
      budget: sandbox_policy.default_budget(),
      abilities: capability.allow([]),
      direct_host_ffi: False,
      native_jets: True,
      external_executor: Some(
        sandbox_policy.ExternalExecutor(
          name: "test",
          launcher: fn(_input, _budget) { Ok("external") },
        ),
      ),
    )
  let assert Error(refusal) = sandbox_policy.admit(policy)
  sandbox_policy.refusal_name(refusal) |> should.equal("native_jet_denied")
}

pub fn invalid_budget_refuses_before_executor_check_test() {
  let budget =
    sandbox_policy.ResourceBudget(
      deadline_ms: 0,
      max_processes: 1,
      max_memory_bytes: 1,
      max_reductions: 1,
      max_concurrency: 1,
    )
  let policy =
    sandbox_policy.SandboxPolicy(
      profile: sandbox_policy.UntrustedExecution,
      budget: budget,
      abilities: capability.allow([]),
      direct_host_ffi: False,
      native_jets: False,
      external_executor: None,
    )
  let assert Error(refusal) = sandbox_policy.admit(policy)
  sandbox_policy.refusal_name(refusal)
  |> should.equal("invalid_resource_budget")
}

pub fn valid_untrusted_profile_with_executor_is_admitted_test() {
  let executor =
    sandbox_policy.ExternalExecutor(
      name: "test-executor",
      launcher: fn(_input, _budget) { Ok("external") },
    )
  let policy = sandbox_policy.untrusted(capability.allow([]), Some(executor))
  sandbox_policy.admit(policy) |> should.equal(Ok(policy))
  sandbox_policy.profile_denies_host_authority(policy) |> should.be_true
}

pub fn untrusted_execution_delegates_to_external_executor_test() {
  let executor =
    sandbox_policy.ExternalExecutor(
      name: "test-executor",
      launcher: fn(input, budget) {
        case budget.deadline_ms {
          30_000 -> Ok("external:" <> input)
          _ -> Error("wrong_budget")
        }
      },
    )
  let policy = sandbox_policy.untrusted(capability.allow([]), Some(executor))
  sandbox_policy.execute(policy, "payload")
  |> should.equal(Ok("external:payload"))
}

pub fn untrusted_execute_without_executor_refuses_test() {
  let policy = sandbox_policy.untrusted(capability.allow([]), None)
  sandbox_policy.execute(policy, "payload")
  |> should.equal(Error("missing_external_executor"))
}

pub fn host_authority_capability_names_are_rejected_test() {
  sandbox_policy.require_no_host_authority(["m_safe"])
  |> should.equal(Ok(Nil))
  sandbox_policy.require_no_host_authority(["m_native_ffi"])
  |> should.be_error
  Some("present") |> should.equal(Some("present"))
  None |> should.equal(None)
}
