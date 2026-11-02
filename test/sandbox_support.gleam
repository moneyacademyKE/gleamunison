//// Test-side sandbox-policy scaffolding (bk-b282): these five surfaces had
//// zero production callers — the erl transport routes through
//// admit_profile/1 (string profile, no records), mcp_write through
//// denies_untrusted_execution, and nothing in src builds an
//// AuthenticatedRemote policy outside admit_profile itself. They stay
//// shape-identical here; the boundary tests that pin them live in test/.

import gleam/list
import gleam/option.{None}
import gleam/string
import gleamunison/capability
import gleamunison/sandbox_policy.{
  type ExecutionProfile, type SandboxPolicy, AuthenticatedRemote, Local,
  UntrustedExecution,
}

pub fn authenticated_remote(abilities: capability.Policy) -> SandboxPolicy {
  sandbox_policy.SandboxPolicy(
    profile: AuthenticatedRemote,
    budget: sandbox_policy.default_budget(),
    abilities: abilities,
    direct_host_ffi: True,
    external_executor: None,
  )
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

pub fn require_no_host_authority(keys: List(String)) -> Result(Nil, String) {
  case list.find(keys, is_host_authority_key) {
    Ok(key) -> Error("untrusted profile refuses host authority: " <> key)
    Error(Nil) -> Ok(Nil)
  }
}

fn is_host_authority_key(key: String) -> Bool {
  string.contains(key, "ffi")
}
