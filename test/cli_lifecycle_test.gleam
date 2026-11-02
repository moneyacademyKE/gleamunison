//// Store lifecycle: where the store lives and whether a run trusts it. Both
//// are environment reads, so both are resolved in one place and asserted here
//// rather than discovered at a call site.

import envoy
import gleam/option.{None, Some}
import gleam/string
import gleamunison/cli_lifecycle
import gleamunison/cli_result
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

fn with_branch(value: String, check: fn() -> a) -> a {
  envoy.set("GLEAMUNISON_BRANCH", value)
  let result = check()
  envoy.unset("GLEAMUNISON_BRANCH")
  result
}

/// Branch resolution reads the live configuration file, so the default is
/// asserted against a path that does not exist: otherwise a gleamunison.toml
/// sitting in the working directory could supply the answer under test.
fn with_absent_config(check: fn() -> a) -> a {
  envoy.set("GLEAMUNISON_CONFIG", "/tmp/gleamunison-branch-absent.toml")
  let result = check()
  envoy.unset("GLEAMUNISON_CONFIG")
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

/// The branch default is one decision with one owner: purge, unpublish, pkg and
/// run take it from here instead of each declaring its own "main".
pub fn the_default_branch_is_main_test() {
  cli_lifecycle.default_branch |> should.equal("main")
}

/// resolve_branch walks the same CLI > TOML > env chain the store dir does, so
/// the branch a session binds to is configuration rather than a decision made
/// inside the session module that used to hold it.
pub fn the_selected_branch_defaults_to_the_branch_default_test() {
  envoy.unset("GLEAMUNISON_BRANCH")
  with_absent_config(fn() {
    cli_lifecycle.resolve_branch()
    |> should.equal(Ok(cli_lifecycle.default_branch))
  })
}

pub fn an_environment_branch_override_wins_test() {
  with_absent_config(fn() {
    with_branch("dev", fn() {
      cli_lifecycle.resolve_branch() |> should.equal(Ok("dev"))
    })
  })
}

/// An empty override is treated as absent by config.string_or, which matters
/// here more than elsewhere: an empty branch name would silently bind a
/// session to nothing rather than falling back.
pub fn an_empty_branch_override_falls_back_to_the_default_test() {
  with_absent_config(fn() {
    with_branch("", fn() {
      cli_lifecycle.resolve_branch() |> should.equal(Ok("main"))
    })
  })
}

pub fn a_toml_branch_beats_the_environment_test() {
  let dir = "/tmp/gleamunison-config-branch-test"
  let config_path = dir <> "/gleamunison.toml"
  let assert Ok(_) = simplifile.create_directory_all(dir)
  let assert Ok(_) =
    simplifile.write(config_path, "GLEAMUNISON_BRANCH = \"release\"\n")

  envoy.set("GLEAMUNISON_CONFIG", config_path)
  envoy.set("GLEAMUNISON_BRANCH", "dev")
  let result = cli_lifecycle.resolve_branch()
  envoy.unset("GLEAMUNISON_CONFIG")
  envoy.unset("GLEAMUNISON_BRANCH")
  let _ = simplifile.delete(config_path)
  let _ = simplifile.delete(dir)

  result |> should.equal(Ok("release"))
}

/// purge and unpublish refuse a valueless --store with exactly these bytes and
/// this exit code. The wording used to be written out in both files, where the
/// two could drift apart without either command noticing.
pub fn a_valueless_store_flag_refuses_with_the_usage_test() {
  cli_lifecycle.missing_store_value("USAGE")
  |> should.equal(#(cli_result.refused, "--store needs a path\nUSAGE"))
}

pub fn a_valueless_branch_flag_refuses_with_the_usage_test() {
  cli_lifecycle.missing_branch_value("USAGE")
  |> should.equal(#(cli_result.refused, "--branch needs a name\nUSAGE"))
}

/// The shared flag tail: branch is an accumulator carrying the default, so a
/// command needs one parser no matter where --branch appears. cli_pkg grew a
/// second parser for exactly this and the second one forgot flags.
pub fn the_flag_tail_starts_on_the_default_branch_test() {
  let tail = cli_lifecycle.flag_tail(cli_lifecycle.default_branch)
  tail.branch |> should.equal("main")
  tail.store |> should.equal(None)
}

pub fn the_flag_tail_takes_store_and_branch_in_any_order_test() {
  let tail = cli_lifecycle.flag_tail("main")
  let assert cli_lifecycle.Taken(after_branch, rest) =
    cli_lifecycle.take_flag(["--branch", "dev", "--store", "/tmp/s"], tail)
  rest |> should.equal(["--store", "/tmp/s"])
  let assert cli_lifecycle.Taken(after_store, rest2) =
    cli_lifecycle.take_flag(rest, after_branch)
  rest2 |> should.equal([])
  after_store.branch |> should.equal("dev")
  after_store.store |> should.equal(Some("/tmp/s"))
}

pub fn the_flag_tail_reports_a_valueless_flag_test() {
  let tail = cli_lifecycle.flag_tail("main")
  cli_lifecycle.take_flag(["--store"], tail)
  |> should.equal(cli_lifecycle.MissingValue("--store"))
  cli_lifecycle.take_flag(["--branch"], tail)
  |> should.equal(cli_lifecycle.MissingValue("--branch"))
}

pub fn the_flag_tail_leaves_other_arguments_to_the_caller_test() {
  let tail = cli_lifecycle.flag_tail("main")
  cli_lifecycle.take_flag([], tail) |> should.equal(cli_lifecycle.NotTailFlag)
  cli_lifecycle.take_flag(["abc123"], tail)
  |> should.equal(cli_lifecycle.NotTailFlag)
  cli_lifecycle.take_flag(["--peer", "host:9"], tail)
  |> should.equal(cli_lifecycle.NotTailFlag)
}
