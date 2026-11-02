import gleam/dynamic.{type Dynamic}
import gleam/option.{type Option, None, Some}
import gleamunison/capability
import gleamunison/dynamic_ffi.{from_dynamic, to_dynamic}

@external(erlang, "gleamunison_eval_scope", "run_bounded")
fn ffi_run_bounded(
  work: fn() -> Dynamic,
  deadline_ms: Int,
  max_processes: Int,
  max_reductions: Int,
  max_memory_bytes: Int,
) -> Result(Dynamic, String)

pub type ExecutionProfile {
  Local
  AuthenticatedRemote
  UntrustedExecution
}

pub type ResourceBudget {
  ResourceBudget(
    deadline_ms: Int,
    max_processes: Int,
    max_memory_bytes: Int,
    max_reductions: Int,
    max_concurrency: Int,
  )
}

pub type ExternalExecutor {
  ExternalExecutor(
    name: String,
    launcher: fn(String, ResourceBudget) -> Result(String, String),
  )
}

pub type SandboxPolicy {
  SandboxPolicy(
    profile: ExecutionProfile,
    budget: ResourceBudget,
    abilities: capability.Policy,
    direct_host_ffi: Bool,
    external_executor: Option(ExternalExecutor),
  )
}

pub type BoundaryRefusal {
  MissingExternalExecutor
  DirectHostFfiDenied
  InvalidResourceBudget
}

pub fn default_budget() -> ResourceBudget {
  ResourceBudget(
    deadline_ms: 30_000,
    max_processes: 1024,
    max_memory_bytes: 256 * 1024 * 1024,
    max_reductions: 10_000_000,
    max_concurrency: 64,
  )
}

pub fn local(abilities: capability.Policy) -> SandboxPolicy {
  SandboxPolicy(
    profile: Local,
    budget: default_budget(),
    abilities: abilities,
    direct_host_ffi: True,
    external_executor: None,
  )
}

fn authenticated_remote(abilities: capability.Policy) -> SandboxPolicy {
  SandboxPolicy(
    profile: AuthenticatedRemote,
    budget: default_budget(),
    abilities: abilities,
    direct_host_ffi: True,
    external_executor: None,
  )
}

pub fn untrusted(
  abilities: capability.Policy,
  external_executor: Option(ExternalExecutor),
) -> SandboxPolicy {
  SandboxPolicy(
    profile: UntrustedExecution,
    budget: default_budget(),
    abilities: abilities,
    direct_host_ffi: False,
    external_executor: external_executor,
  )
}

pub fn admit(policy: SandboxPolicy) -> Result(SandboxPolicy, BoundaryRefusal) {
  case valid_budget(policy.budget) {
    False -> Error(InvalidResourceBudget)
    True ->
      case policy {
        SandboxPolicy(profile: UntrustedExecution, external_executor: None, ..) ->
          Error(MissingExternalExecutor)
        SandboxPolicy(profile: UntrustedExecution, direct_host_ffi: True, ..) ->
          Error(DirectHostFfiDenied)
        _ -> Ok(policy)
      }
  }
}

pub fn execute(policy: SandboxPolicy, input: String) -> Result(String, String) {
  case admit(policy) {
    Error(refusal) -> Error(refusal_name(refusal))
    Ok(policy) ->
      case policy.profile {
        UntrustedExecution ->
          case policy.external_executor {
            Some(executor) -> executor.launcher(input, policy.budget)
            None -> Error("missing_external_executor")
          }
        _ ->
          ffi_run_bounded(
            fn() { to_dynamic(Ok(input)) },
            policy.budget.deadline_ms,
            policy.budget.max_processes,
            policy.budget.max_reductions,
            policy.budget.max_memory_bytes,
          )
          |> fn(result) {
            case result {
              Ok(dynamic) -> from_dynamic(dynamic)
              Error(reason) -> Error(reason)
            }
          }
      }
  }
}

pub fn refusal_name(refusal: BoundaryRefusal) -> String {
  case refusal {
    MissingExternalExecutor -> "missing_external_executor"
    DirectHostFfiDenied -> "direct_host_ffi_denied"
    InvalidResourceBudget -> "invalid_resource_budget"
  }
}

fn valid_budget(budget: ResourceBudget) -> Bool {
  budget.deadline_ms > 0
  && budget.deadline_ms <= 300_000
  && budget.max_processes > 0
  && budget.max_processes <= 1024
  && budget.max_memory_bytes > 0
  && budget.max_memory_bytes <= 4 * 1024 * 1024 * 1024
  && budget.max_reductions > 0
  && budget.max_reductions <= 1_000_000_000
  && budget.max_concurrency > 0
  && budget.max_concurrency <= 1024
}

/// Transport-facing admission. An Erlang route knows the deployment profile
/// name from the environment, not a Gleam record, so this builds the policy
/// for that name and admits it. Ok means the profile may serve untrusted
/// work; Error carries the refusal name.
///
/// This is the enforcement point the README claims: the untrusted-execution
/// profile refuses until a real external executor exists, and it refuses
/// direct host FFI by construction.
pub fn admit_profile(profile: String) -> Result(Nil, String) {
  let policy = case profile {
    "untrusted-execution" -> untrusted(capability.allow([]), None)
    "authenticated-remote" -> authenticated_remote(capability.allow([]))
    _ -> local(capability.allow([]))
  }
  case admit(policy) {
    Ok(_) -> Ok(Nil)
    Error(refusal) -> Error(refusal_name(refusal))
  }
}

pub fn denies_untrusted_execution(profile: String) -> Bool {
  profile == "untrusted-execution"
}
