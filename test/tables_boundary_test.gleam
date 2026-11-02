/// bk-09d9: gleamunison_tables:ensure/2 is the one owner of the ETS
/// ensure-table idiom folded in from five hand-rolled copies. These tests
/// pin the contract the five callers rely on: idempotence, freedom from
/// the concurrent-create race (the whereis-only copies could crash with
/// badarg when a table appeared between check and create), and exact
/// preservation of the caller's table options.
@external(erlang, "tables_boundary_ffi", "double_ensure_ok")
fn double_ensure_ok() -> Bool

@external(erlang, "tables_boundary_ffi", "concurrent_ensure_ok")
fn concurrent_ensure_ok() -> Bool

@external(erlang, "tables_boundary_ffi", "options_preserved")
fn options_preserved() -> Bool

pub fn tables_double_ensure_is_idempotent_test() {
  assert double_ensure_ok()
}

pub fn tables_concurrent_ensure_never_crashes_test() {
  assert concurrent_ensure_ok()
}

pub fn tables_ensure_preserves_caller_options_test() {
  assert options_preserved()
}
