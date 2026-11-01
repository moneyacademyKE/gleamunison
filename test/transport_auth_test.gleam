import gleamunison/auth
import gleeunit/should

pub fn public_routes_require_no_identity_test() {
  auth.required_scope("/") |> should.equal(auth.Public)
  auth.required_scope("/api/live") |> should.equal(auth.Public)
  auth.required_scope("/api/ready") |> should.equal(auth.Public)
  auth.required_scope("/static/app.js") |> should.equal(auth.Public)
  auth.authorize_scopes([auth.Public], "/api/live") |> should.be_ok
}

pub fn write_routes_require_data_write_test() {
  auth.required_scope("/eval") |> should.equal(auth.DataWrite)
  auth.required_scope("/define") |> should.equal(auth.DataWrite)
  auth.required_scope("/mcp") |> should.equal(auth.DataWrite)
  auth.required_scope("/app/greeting") |> should.equal(auth.DataWrite)
  // An anonymous caller resolves to public scope only; the credential→scopes
  // resolution itself lives in erl (gleamunison_http:token_scopes/1).
  auth.authorize_scopes([auth.Public], "/eval") |> should.be_error
  auth.authorize_scopes([auth.Public], "/app/greeting") |> should.be_error
}

pub fn api_routes_require_admin_test() {
  auth.required_scope("/api/status") |> should.equal(auth.Admin)
  auth.required_scope("/api/traces") |> should.equal(auth.Admin)
  auth.authorize_scopes([auth.Public], "/api/status") |> should.be_error
}

pub fn admin_scope_authorizes_write_routes_test() {
  auth.authorize_scopes([auth.Admin], "/eval") |> should.be_ok
  auth.authorize_scopes([auth.Admin], "/mcp") |> should.be_ok
  auth.authorize_scopes([auth.Admin], "/api/status") |> should.be_ok
}

pub fn read_scoped_token_cannot_reach_admin_routes_test() {
  let reader = [auth.Public, auth.DataRead]
  auth.authorize_scopes(reader, "/api/live") |> should.be_ok
  auth.authorize_scopes(reader, "/api/status") |> should.be_error
  auth.authorize_scopes(reader, "/eval") |> should.be_error
}

pub fn write_scoped_token_cannot_reach_admin_routes_test() {
  let writer = [auth.Public, auth.DataRead, auth.DataWrite]
  auth.authorize_scopes(writer, "/eval") |> should.be_ok
  auth.authorize_scopes(writer, "/define") |> should.be_ok
  auth.authorize_scopes(writer, "/api/traces") |> should.be_error
}

pub fn authorize_scopes_is_the_whole_decision_test() {
  auth.authorize_scopes([auth.Public], "/api/ready") |> should.be_ok
  auth.authorize_scopes([auth.Public], "/api/status") |> should.be_error
  auth.authorize_scopes([auth.DataWrite], "/api/status") |> should.be_error
  auth.authorize_scopes([auth.Admin], "/api/status") |> should.be_ok
  auth.authorize_scopes([], "/") |> should.be_ok
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
