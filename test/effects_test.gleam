pub fn storage_owner_survives_test() {
  let assert Ok(Nil) = ffi_test_storage_owner_survives()
}

pub fn effects_runtime_test() {
  let assert Ok(Nil) = ffi_test_effects_runtime()
}

@external(erlang, "gleamunison_ffi", "test_storage_owner_survives")
fn ffi_test_storage_owner_survives() -> Result(Nil, String)

@external(erlang, "gleamunison_ffi", "test_effects_runtime")
fn ffi_test_effects_runtime() -> Result(Nil, String)
