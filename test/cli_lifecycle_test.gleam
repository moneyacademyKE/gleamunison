//// Store lifecycle: where the store lives and whether a run trusts it. Both
//// are environment reads, so both are resolved in one place and asserted here
//// rather than discovered at a call site.

import gleam/option.{Some}
import gleamunison/cli_lifecycle
import gleeunit/should

@external(erlang, "gleamunison_ffi_test", "set_env")
fn set_env(key: String, value: String) -> Nil

@external(erlang, "gleamunison_ffi_test", "unset_env")
fn unset_env(key: String) -> Nil

fn with_store_dir(value: String, check: fn() -> a) -> a {
  set_env("GLEAMUNISON_STORE_DIR", value)
  let result = check()
  unset_env("GLEAMUNISON_STORE_DIR")
  result
}

fn with_allow_unverified(value: String, check: fn() -> a) -> a {
  set_env("GLEAMUNISON_STORE_ALLOW_UNVERIFIED", value)
  let result = check()
  unset_env("GLEAMUNISON_STORE_ALLOW_UNVERIFIED")
  result
}

pub fn the_default_store_dir_is_dot_gleamunison_test() {
  unset_env("GLEAMUNISON_STORE_DIR")
  cli_lifecycle.resolve_store_dir() |> should.equal(Ok(".gleamunison"))
  cli_lifecycle.resolve_store_path()
  |> should.equal(Ok(".gleamunison/store.dets"))
}

pub fn an_absolute_override_wins_test() {
  with_store_dir("/tmp/some-store", fn() {
    cli_lifecycle.resolve_store_dir() |> should.equal(Ok("/tmp/some-store"))
  })
}

pub fn a_trailing_slash_is_not_doubled_test() {
  with_store_dir("/tmp/some-store/", fn() {
    cli_lifecycle.resolve_store_path()
    |> should.equal(Ok("/tmp/some-store/store.dets"))
  })
}

pub fn a_relative_override_is_refused_test() {
  // A relative store resolved against the wrong working directory looks
  // empty, and an empty store reads as "your definition was never published".
  with_store_dir("relative/store", fn() {
    let assert Error(message) = cli_lifecycle.resolve_store_dir()
    message
    |> should.equal(
      "GLEAMUNISON_STORE_DIR must be an absolute path, got: relative/store",
    )
  })
}

pub fn an_explicit_store_context_owns_siblings_test() {
  let assert Ok(context) =
    cli_lifecycle.resolve_context(Some("/tmp/selected/store.dets"))
  cli_lifecycle.store_path(context)
  |> should.equal("/tmp/selected/store.dets")
  cli_lifecycle.manifest_path(context)
  |> should.equal("/tmp/selected/published")
  cli_lifecycle.root_dir(context) |> should.equal("/tmp/selected")
}

pub fn a_relative_explicit_store_is_refused_test() {
  let assert Error(message) =
    cli_lifecycle.resolve_context(Some("relative/store.dets"))
  message
  |> should.equal("store path must be absolute, got: relative/store.dets")
}

pub fn an_empty_override_falls_back_to_the_default_test() {
  with_store_dir("", fn() {
    cli_lifecycle.resolve_store_dir() |> should.equal(Ok(".gleamunison"))
  })
}

pub fn verification_is_on_by_default_test() {
  unset_env("GLEAMUNISON_STORE_ALLOW_UNVERIFIED")
  cli_lifecycle.resolve_allow_unverified() |> should.be_false
}

pub fn the_escape_hatch_accepts_the_usual_spellings_test() {
  with_allow_unverified("1", fn() {
    cli_lifecycle.resolve_allow_unverified() |> should.be_true
  })
  with_allow_unverified("true", fn() {
    cli_lifecycle.resolve_allow_unverified() |> should.be_true
  })
  with_allow_unverified("TRUE", fn() {
    cli_lifecycle.resolve_allow_unverified() |> should.be_true
  })
}

pub fn any_other_value_leaves_verification_on_test() {
  with_allow_unverified("0", fn() {
    cli_lifecycle.resolve_allow_unverified() |> should.be_false
  })
  with_allow_unverified("nope", fn() {
    cli_lifecycle.resolve_allow_unverified() |> should.be_false
  })
}
