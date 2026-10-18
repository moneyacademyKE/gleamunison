//// The package version exposed by protocol surfaces.
//// The application manifest generated from gleam.toml is the single source.

@external(erlang, "gleamunison_ffi", "application_version")
fn ffi_application_version() -> String

pub fn current() -> String {
  ffi_application_version()
}
