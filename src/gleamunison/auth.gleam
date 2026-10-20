//// Typed request identity, scopes, and bind policy.
////
//// Data over dispatch: routes map to scopes, identities carry scopes, and
//// authorization is a pure decision. The Erlang HTTP/sync servers call
//// required_scope/1 and bind_decision/3; they do not re-implement policy.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type Scope {
  Public
  DataRead
  DataWrite
  Admin
}

pub type Identity {
  Anonymous
  LocalPeer
  Bearer(token_hash: String)
  ProxyPrincipal(name: String, scopes: List(Scope))
}

pub type BindDecision {
  Allow
  Refuse(reason: String)
}

pub type BindInput {
  BindInput(
    address: String,
    profile: String,
    http_token_present: Bool,
    sync_token_present: Bool,
  )
}

pub fn required_scope(path: String) -> Scope {
  case path {
    "/" -> Public
    "/index.html" -> Public
    "/api/live" -> Public
    "/api/ready" -> Public
    "/api/health" -> Public
    _ ->
      case string.starts_with(path, "/static/") {
        True -> Public
        False ->
          case path {
            "/eval" -> DataWrite
            "/define" -> DataWrite
            "/mcp" -> DataWrite
            _ ->
              case string.starts_with(path, "/api/") {
                True -> Admin
                False -> DataWrite
              }
          }
      }
  }
}

pub fn scope_name(scope: Scope) -> String {
  case scope {
    Public -> "public"
    DataRead -> "data-read"
    DataWrite -> "data-write"
    Admin -> "admin"
  }
}

pub fn scope_at_least(have: Scope, need: Scope) -> Bool {
  rank(have) >= rank(need)
}

fn rank(scope: Scope) -> Int {
  case scope {
    Public -> 0
    DataRead -> 1
    DataWrite -> 2
    Admin -> 3
  }
}

pub fn identity_scopes(identity: Identity) -> List(Scope) {
  case identity {
    Anonymous -> [Public]
    LocalPeer -> [Public, DataRead, DataWrite, Admin]
    Bearer(_) -> [Public, DataRead, DataWrite, Admin]
    ProxyPrincipal(_, scopes) -> scopes
  }
}

pub fn authorize(identity: Identity, path: String) -> Result(Identity, String) {
  let need = required_scope(path)
  case need {
    Public -> Ok(identity)
    _ ->
      case
        list.any(identity_scopes(identity), fn(s) { scope_at_least(s, need) })
      {
        True -> Ok(identity)
        False -> Error("insufficient_scope:" <> scope_name(need))
      }
  }
}

pub fn bearer_identity(token: Option(String)) -> Identity {
  case token {
    None -> Anonymous
    Some("") -> Anonymous
    Some(_) -> Bearer("bearer:present")
  }
}

/// Non-loopback binding is a refusal boundary, not a configuration option.
/// Loopback binds always allow. Remote binds require the authenticated-remote
/// profile and an authentication contract (HTTP token for the reverse proxy;
/// direct TLS termination is intentionally not implemented in this runtime).
pub fn bind_decision(input: BindInput) -> BindDecision {
  case is_loopback(input.address) {
    True -> Allow
    False ->
      case input.profile == "authenticated-remote" {
        False -> Refuse("non_loopback_requires_authenticated_remote_profile")
        True ->
          case input.http_token_present {
            True -> Allow
            False -> Refuse("non_loopback_requires_auth_contract")
          }
      }
  }
}

pub fn is_loopback(address: String) -> Bool {
  address == "127.0.0.1"
  || address == "::1"
  || address == "localhost"
  || string.starts_with(address, "127.")
}
