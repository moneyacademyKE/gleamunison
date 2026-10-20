import gleam/option.{None, Some}
import gleamunison/auth
import gleeunit/should

pub fn public_routes_require_no_identity_test() {
  auth.required_scope("/") |> should.equal(auth.Public)
  auth.required_scope("/api/live") |> should.equal(auth.Public)
  auth.required_scope("/api/ready") |> should.equal(auth.Public)
  auth.required_scope("/static/app.js") |> should.equal(auth.Public)
  auth.authorize(auth.Anonymous, "/api/live") |> should.be_ok
}

pub fn write_routes_require_data_write_test() {
  auth.required_scope("/eval") |> should.equal(auth.DataWrite)
  auth.required_scope("/define") |> should.equal(auth.DataWrite)
  auth.required_scope("/mcp") |> should.equal(auth.DataWrite)
  auth.authorize(auth.Anonymous, "/eval") |> should.be_error
}

pub fn api_routes_require_admin_test() {
  auth.required_scope("/api/status") |> should.equal(auth.Admin)
  auth.required_scope("/api/traces") |> should.equal(auth.Admin)
  auth.authorize(auth.Anonymous, "/api/status") |> should.be_error
}

pub fn bearer_identity_authorizes_write_routes_test() {
  let identity = auth.bearer_identity(Some("server-secret"))
  auth.authorize(identity, "/eval") |> should.be_ok
  auth.authorize(identity, "/mcp") |> should.be_ok
  auth.authorize(identity, "/api/status") |> should.be_ok
}

pub fn empty_bearer_token_is_anonymous_test() {
  auth.bearer_identity(None) |> should.equal(auth.Anonymous)
  auth.bearer_identity(Some("")) |> should.equal(auth.Anonymous)
  auth.authorize(auth.bearer_identity(None), "/define") |> should.be_error
}

pub fn proxy_principal_scopes_are_enforced_test() {
  let reader = auth.ProxyPrincipal("ci", [auth.Public, auth.DataRead])
  auth.authorize(reader, "/api/live") |> should.be_ok
  auth.authorize(reader, "/eval") |> should.be_error
  auth.authorize(reader, "/api/status") |> should.be_error
}

pub fn loopback_bind_always_allowed_test() {
  auth.bind_decision(auth.BindInput(
    address: "127.0.0.1",
    profile: "local",
    http_token_present: False,
    sync_token_present: False,
  ))
  |> should.equal(auth.Allow)
}

pub fn non_loopback_requires_profile_and_auth_contract_test() {
  let missing_profile =
    auth.BindInput(
      address: "0.0.0.0",
      profile: "local",
      http_token_present: True,
      sync_token_present: False,
    )
  let assert auth.Refuse(reason) = auth.bind_decision(missing_profile)
  reason |> should.equal("non_loopback_requires_authenticated_remote_profile")

  let missing_auth =
    auth.BindInput(
      address: "0.0.0.0",
      profile: "authenticated-remote",
      http_token_present: False,
      sync_token_present: False,
    )
  let assert auth.Refuse(reason2) = auth.bind_decision(missing_auth)
  reason2 |> should.equal("non_loopback_requires_auth_contract")

  auth.bind_decision(auth.BindInput(
    address: "0.0.0.0",
    profile: "authenticated-remote",
    http_token_present: True,
    sync_token_present: False,
  ))
  |> should.equal(auth.Allow)
}
