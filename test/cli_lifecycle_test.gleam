//// Store lifecycle: where the store lives and whether a run trusts it. Both
//// are environment reads, so both are resolved in one place and asserted here
//// rather than discovered at a call site.

import envoy
import gleam/option.{Some}
import gleam/string
import gleamunison/cli_lifecycle
import gleeunit/should
import simplifile

fn with_store_dir(value: String, check: fn() -> a) -> a {
  envoy.set("GLEAMUNISON_STORE_DIR", value)
  let result = check()
  envoy.unset("GLEAMUNISON_STORE_DIR")
  result
}

fn with_allow_unverified(value: String, check: fn() -> a) -> a {
  envoy.set("GLEAMUNISON_STORE_ALLOW_UNVERIFIED", value)
  let result = check()
  envoy.unset("GLEAMUNISON_STORE_ALLOW_UNVERIFIED")
  result
}

pub fn the_default_store_dir_is_dot_gleamunison_test() {
  envoy.unset("GLEAMUNISON_STORE_DIR")
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
  envoy.unset("GLEAMUNISON_STORE_ALLOW_UNVERIFIED")
  cli_lifecycle.resolve_allow_unverified() |> should.equal(Ok(False))
}

pub fn the_escape_hatch_accepts_the_usual_spellings_test() {
  with_allow_unverified("1", fn() {
    cli_lifecycle.resolve_allow_unverified() |> should.equal(Ok(True))
  })
  with_allow_unverified("true", fn() {
    cli_lifecycle.resolve_allow_unverified() |> should.equal(Ok(True))
  })
  with_allow_unverified("TRUE", fn() {
    cli_lifecycle.resolve_allow_unverified() |> should.equal(Ok(True))
  })
}

pub fn any_other_value_leaves_verification_on_test() {
  with_allow_unverified("0", fn() {
    cli_lifecycle.resolve_allow_unverified() |> should.equal(Ok(False))
  })
  with_allow_unverified("nope", fn() {
    cli_lifecycle.resolve_allow_unverified() |> should.equal(Ok(False))
  })
}

pub fn a_toml_store_dir_beats_the_environment_test() {
  let dir = "/tmp/gleamunison-config-store-test"
  let config_path = dir <> "/gleamunison.toml"
  let assert Ok(_) = simplifile.create_directory_all(dir)
  let assert Ok(_) =
    simplifile.write(
      config_path,
      "GLEAMUNISON_STORE_DIR = \"/tmp/toml-store\"\n",
    )

  envoy.set("GLEAMUNISON_CONFIG", config_path)
  envoy.set("GLEAMUNISON_STORE_DIR", "/tmp/env-store")
  let result = cli_lifecycle.resolve_store_dir()
  envoy.unset("GLEAMUNISON_CONFIG")
  envoy.unset("GLEAMUNISON_STORE_DIR")
  let _ = simplifile.delete(config_path)
  let _ = simplifile.delete(dir)

  result |> should.equal(Ok("/tmp/toml-store"))
}

pub fn a_malformed_config_file_is_reported_test() {
  let dir = "/tmp/gleamunison-config-malformed-test"
  let config_path = dir <> "/gleamunison.toml"
  let assert Ok(_) = simplifile.create_directory_all(dir)
  let assert Ok(_) = simplifile.write(config_path, "GLEAMUNISON_STORE_DIR =\n")

  envoy.set("GLEAMUNISON_CONFIG", config_path)
  let result = cli_lifecycle.resolve_store_dir()
  envoy.unset("GLEAMUNISON_CONFIG")
  let _ = simplifile.delete(config_path)
  let _ = simplifile.delete(dir)

  case result {
    Error(message) -> {
      string.contains(message, config_path) |> should.be_true
      string.contains(message, "unexpected") |> should.be_true
    }
    Ok(_) -> panic as "malformed configuration was silently ignored"
  }
}
