import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleamunison/capability

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
    native_jets: Bool,
    external_executor: Option(ExternalExecutor),
  )
}

pub type BoundaryRefusal {
  MissingExternalExecutor
  DirectHostFfiDenied
  NativeJetDenied
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
    native_jets: True,
    external_executor: None,
  )
}

pub fn authenticated_remote(abilities: capability.Policy) -> SandboxPolicy {
  SandboxPolicy(
    profile: AuthenticatedRemote,
    budget: default_budget(),
    abilities: abilities,
    direct_host_ffi: True,
    native_jets: True,
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
    native_jets: False,
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
        SandboxPolicy(profile: UntrustedExecution, native_jets: True, ..) ->
          Error(NativeJetDenied)
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

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn to_dynamic(value: a) -> Dynamic

@external(erlang, "gleamunison_ffi", "from_dynamic")
fn from_dynamic(value: Dynamic) -> a

pub fn refusal_name(refusal: BoundaryRefusal) -> String {
  case refusal {
    MissingExternalExecutor -> "missing_external_executor"
    DirectHostFfiDenied -> "direct_host_ffi_denied"
    NativeJetDenied -> "native_jet_denied"
    InvalidResourceBudget -> "invalid_resource_budget"
  }
}

pub fn profile_name(profile: ExecutionProfile) -> String {
  case profile {
    Local -> "local"
    AuthenticatedRemote -> "authenticated-remote"
    UntrustedExecution -> "untrusted-execution"
  }
}

pub fn capability_refusals(
  _policy: SandboxPolicy,
  denied: List(String),
) -> List(String) {
  list.map(denied, fn(key) { "capability_denied:" <> key })
}

pub fn profile_denies_host_authority(policy: SandboxPolicy) -> Bool {
  case policy.profile {
    UntrustedExecution -> True
    _ -> False
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

pub fn require_no_host_authority(keys: List(String)) -> Result(Nil, String) {
  case list.find(keys, is_host_authority_key) {
    Ok(key) -> Error("untrusted profile refuses host authority: " <> key)
    Error(Nil) -> Ok(Nil)
  }
}

fn is_host_authority_key(key: String) -> Bool {
  string.contains(key, "ffi") || string.contains(key, "jet")
}
