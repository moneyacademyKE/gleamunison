pub fn storage_owner_survives_test() {
  let assert Ok(Nil) = ffi_test_storage_owner_survives()
}

pub fn effects_runtime_test() {
  let assert Ok(Nil) = ffi_test_effects_runtime()
}

pub fn ffi_io_coverage_test() {
  let assert Ok(Nil) = ffi_test_ffi_io_coverage()
}

@external(erlang, "gleamunison_ffi_test", "test_storage_owner_survives")
fn ffi_test_storage_owner_survives() -> Result(Nil, String)

@external(erlang, "gleamunison_ffi_test", "test_effects_runtime")
fn ffi_test_effects_runtime() -> Result(Nil, String)

@external(erlang, "gleamunison_ffi_test", "test_ffi_io_coverage")
fn ffi_test_ffi_io_coverage() -> Result(Nil, String)
