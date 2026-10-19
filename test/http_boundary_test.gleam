import gleeunit/should

@external(erlang, "http_boundary_ffi", "static_paths")
fn static_paths() -> Bool

@external(erlang, "http_boundary_ffi", "auth_routes")
fn auth_routes() -> Bool

@external(erlang, "http_boundary_ffi", "symlink_escape")
fn symlink_escape() -> Bool

pub fn static_paths_stay_inside_asset_root_test() {
  static_paths() |> should.be_true
}

pub fn every_data_route_respects_token_gate_test() {
  auth_routes() |> should.be_true
}

pub fn static_symlink_cannot_escape_asset_root_test() {
  symlink_escape() |> should.be_true
}
