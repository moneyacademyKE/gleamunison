import envoy
import gleam/dict
import gleam/option.{None, Some}
import gleam/string
import gleamunison/config.{BoolVal, IntVal, StringVal}
import gleeunit/should
import simplifile

const root = "/tmp/gleamunison-config-precedence-test"

const file_path = "/tmp/gleamunison-config-precedence-test/config.toml"

const absent_path = "/tmp/gleamunison-config-precedence-test/absent.toml"

const key = "GLEAMUNISON_CONFIG_TEST_KEY"

fn with_file(contents: String, check: fn() -> a) -> a {
  let assert Ok(_) = simplifile.create_directory_all(root)
  let assert Ok(_) = simplifile.write(file_path, contents)
  let result = check()
  let _ = simplifile.delete(file_path)
  let _ = simplifile.delete(root)
  result
}

pub fn cli_beats_toml_and_env_test() {
  envoy.set(key, "env")
  with_file(key <> " = \"toml\"\n", fn() {
    let assert Ok(cfg) = config.load_from(file_path)
    let cfg = config.with_cli(cfg, dict.from_list([#(key, StringVal("cli"))]))
    config.optional_string(cfg, key) |> should.equal(Ok(Some("cli")))
  })
  envoy.unset(key)
}

pub fn toml_beats_env_test() {
  envoy.set(key, "env")
  with_file(key <> " = \"toml\"\n", fn() {
    let assert Ok(cfg) = config.load_from(file_path)
    config.optional_string(cfg, key) |> should.equal(Ok(Some("toml")))
  })
  envoy.unset(key)
}

pub fn env_is_the_fallback_test() {
  envoy.set(key, "env")
  let assert Ok(cfg) = config.load_from(absent_path)
  config.optional_string(cfg, key) |> should.equal(Ok(Some("env")))
  envoy.unset(key)
}

pub fn a_missing_file_is_empty_configuration_test() {
  envoy.unset(key)
  let assert Ok(cfg) = config.load_from(absent_path)
  config.optional_string(cfg, key) |> should.equal(Ok(None))
  config.string_or(cfg, key, "default") |> should.equal(Ok("default"))
}

pub fn load_uses_the_selected_config_path_test() {
  with_file(key <> " = \"selected\"\n", fn() {
    envoy.set("GLEAMUNISON_CONFIG", file_path)
    let assert Ok(cfg) = config.load()
    config.optional_string(cfg, key) |> should.equal(Ok(Some("selected")))
    envoy.unset("GLEAMUNISON_CONFIG")
  })
}

pub fn a_malformed_file_is_reported_test() {
  with_file(key <> " =\n", fn() {
    case config.load_from(file_path) {
      Error(message) -> {
        string.contains(message, file_path) |> should.be_true
        string.contains(message, "unexpected") |> should.be_true
      }
      Ok(_) -> panic as "malformed configuration was silently ignored"
    }
  })
}

pub fn a_wrong_toml_type_is_reported_test() {
  with_file(key <> " = 42\n", fn() {
    let assert Ok(cfg) = config.load_from(file_path)
    case config.optional_string(cfg, key) {
      Error(message) -> {
        string.contains(message, key <> " must be a string") |> should.be_true
      }
      Ok(_) -> panic as "an int was accepted as a string"
    }
  })
}

pub fn int_and_bool_settings_use_toml_types_test() {
  with_file("NUMBER = 7\nENABLED = true\n", fn() {
    let assert Ok(cfg) = config.load_from(file_path)
    config.int_or(cfg, "NUMBER", 0) |> should.equal(Ok(7))
    config.flag(cfg, "ENABLED") |> should.equal(Ok(True))
    config.int_or(cfg, "ABSENT", 5) |> should.equal(Ok(5))
    config.flag(cfg, "ABSENT") |> should.equal(Ok(False))
  })
}

pub fn int_and_bool_settings_fall_back_to_env_test() {
  envoy.set("NUMBER", "8")
  envoy.set("ENABLED", "yes")
  let assert Ok(cfg) = config.load_from(absent_path)
  config.int_or(cfg, "NUMBER", 0) |> should.equal(Ok(8))
  config.flag(cfg, "ENABLED") |> should.equal(Ok(True))
  envoy.unset("NUMBER")
  envoy.unset("ENABLED")
}

pub fn cli_int_and_bool_overrides_win_test() {
  with_file("NUMBER = 7\nENABLED = true\n", fn() {
    let assert Ok(cfg) = config.load_from(file_path)
    let cfg =
      config.with_cli(
        cfg,
        dict.from_list([
          #("NUMBER", IntVal(9)),
          #("ENABLED", BoolVal(False)),
        ]),
      )
    config.int_or(cfg, "NUMBER", 0) |> should.equal(Ok(9))
    config.flag(cfg, "ENABLED") |> should.equal(Ok(False))
  })
}

pub fn a_wrong_cli_type_is_reported_test() {
  let cfg = config.with_cli(config.empty(), dict.from_list([#(key, IntVal(1))]))
  case config.optional_string(cfg, key) {
    Error(message) ->
      string.contains(message, key <> " must be a string") |> should.be_true
    Ok(_) -> panic as "an int override was accepted as a string"
  }
}
