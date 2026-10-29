//// Live configuration: CLI overrides beat TOML, and TOML beats environment.
////
//// The previous config module was dead code because no TOML parser existed.
//// This one owns one precedence rule for every process setting, using `tom`
//// for an optional file and `env` for the process fallback. A missing file
//// is normal; a malformed file or wrong value type is an operator error and
//// is surfaced rather than silently ignored.

import gleam/dict.{type Dict}
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleamunison/env
import simplifile
import tom

pub type Value {
  StringVal(String)
  IntVal(Int)
  BoolVal(Bool)
}

pub type Config {
  Config(cli: Dict(String, Value), toml: Dict(String, tom.Toml))
}

const default_path = "gleamunison.toml"

const path_key = "GLEAMUNISON_CONFIG"

pub fn empty() -> Config {
  Config(dict.new(), dict.new())
}

/// The config file selected by `GLEAMUNISON_CONFIG`, else the project default.
pub fn path() -> String {
  env.string_or(path_key, default_path)
}

pub fn load() -> Result(Config, String) {
  load_from(path())
}

pub fn load_from(file_path: String) -> Result(Config, String) {
  use text <- result.try(read_optional(file_path))
  case text {
    None -> Ok(empty())
    Some(contents) ->
      case tom.parse(contents) {
        Ok(table) -> Ok(Config(cli: dict.new(), toml: table))
        Error(error) -> Error(file_path <> ": " <> describe_parse_error(error))
      }
  }
}

pub fn with_cli(config: Config, overrides: Dict(String, Value)) -> Config {
  Config(..config, cli: overrides)
}

pub fn optional_string(
  config: Config,
  key: String,
) -> Result(Option(String), String) {
  case dict.get(config.cli, key) {
    Ok(StringVal(value)) -> Ok(Some(value))
    Ok(other) -> Error(wrong_type(key, "string", classify_cli(other)))
    Error(_) ->
      case tom.get_string(config.toml, [key]) {
        Ok(value) -> Ok(Some(value))
        Error(tom.NotFound(_)) ->
          case env.get(key) {
            Ok(value) -> Ok(Some(value))
            Error(_) -> Ok(None)
          }
        Error(tom.WrongType(_, expected, got)) ->
          Error(wrong_type(key, expected, got))
      }
  }
}

pub fn string_or(
  config: Config,
  key: String,
  default: String,
) -> Result(String, String) {
  use value <- result.try(optional_string(config, key))
  case value {
    Some(text) if text != "" -> Ok(text)
    _ -> Ok(default)
  }
}

pub fn optional_int(
  config: Config,
  key: String,
) -> Result(Option(Int), String) {
  case dict.get(config.cli, key) {
    Ok(IntVal(value)) -> Ok(Some(value))
    Ok(other) -> Error(wrong_type(key, "int", classify_cli(other)))
    Error(_) ->
      case tom.get_int(config.toml, [key]) {
        Ok(value) -> Ok(Some(value))
        Error(tom.NotFound(_)) ->
          case env.get(key) {
            Error(_) -> Ok(None)
            Ok("") -> Ok(None)
            Ok(text) ->
              int.parse(text)
              |> result.replace_error(wrong_type(key, "int", text))
              |> result.map(Some)
          }
        Error(tom.WrongType(_, expected, got)) ->
          Error(wrong_type(key, expected, got))
      }
  }
}

pub fn int_or(
  config: Config,
  key: String,
  default: Int,
) -> Result(Int, String) {
  use value <- result.try(optional_int(config, key))
  case value {
    Some(number) -> Ok(number)
    None -> Ok(default)
  }
}

pub fn optional_bool(
  config: Config,
  key: String,
) -> Result(Option(Bool), String) {
  case dict.get(config.cli, key) {
    Ok(BoolVal(value)) -> Ok(Some(value))
    Ok(other) -> Error(wrong_type(key, "bool", classify_cli(other)))
    Error(_) ->
      case tom.get_bool(config.toml, [key]) {
        Ok(value) -> Ok(Some(value))
        Error(tom.NotFound(_)) ->
          case env.get(key) {
            Error(_) -> Ok(None)
            Ok(text) -> Ok(Some(env.truthy(text)))
          }
        Error(tom.WrongType(_, expected, got)) ->
          Error(wrong_type(key, expected, got))
      }
  }
}

pub fn flag(config: Config, key: String) -> Result(Bool, String) {
  use value <- result.try(optional_bool(config, key))
  case value {
    Some(enabled) -> Ok(enabled)
    None -> Ok(False)
  }
}

fn read_optional(file_path: String) -> Result(Option(String), String) {
  case simplifile.is_file(file_path) {
    Ok(False) -> Ok(None)
    Ok(True) ->
      simplifile.read(file_path)
      |> result.map_error(fn(error) {
        file_path <> ": " <> string.inspect(error)
      })
      |> result.map(Some)
    Error(error) -> Error(file_path <> ": " <> string.inspect(error))
  }
}

fn describe_parse_error(error: tom.ParseError) -> String {
  case error {
    tom.Unexpected(got, expected) ->
      "unexpected " <> got <> ", expected " <> expected
    tom.KeyAlreadyInUse(key) -> "duplicate key: " <> string.join(key, ".")
  }
}

fn wrong_type(key: String, expected: String, got: String) -> String {
  key
  <> " must be a "
  <> string.lowercase(expected)
  <> ", got: "
  <> string.lowercase(got)
}

fn classify_cli(value: Value) -> String {
  case value {
    StringVal(_) -> "string"
    IntVal(_) -> "int"
    BoolVal(_) -> "bool"
  }
}
