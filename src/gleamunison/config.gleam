import gleam/dict.{type Dict}
import gleam/list

pub type ConfigValue {
  StringVal(String)
  IntVal(Int)
  BoolVal(Bool)
}

pub type Config {
  Config(env: Dict(String, ConfigValue), toml: Dict(String, ConfigValue), cli: Dict(String, ConfigValue))
}

@external(erlang, "gleamunison_config", "get_all_env")
fn ffi_get_all_env() -> List(#(String, String))

pub fn load() -> Config {
  let pairs = ffi_get_all_env()
  let env = list.fold(pairs, dict.new(), fn(acc, pair) {
    let #(k, v) = pair
    dict.insert(acc, k, StringVal(v))
  })
  Config(env, dict.new(), dict.new())
}

pub fn with_cli(config: Config, overrides: Dict(String, ConfigValue)) -> Config {
  Config(..config, cli: overrides)
}

pub fn get(config: Config, key: String) -> Result(ConfigValue, Nil) {
  case dict.get(config.cli, key) {
    Ok(v) -> Ok(v)
    Error(_) ->
      case dict.get(config.toml, key) {
        Ok(v) -> Ok(v)
        Error(_) -> dict.get(config.env, key)
      }
  }
}

pub fn get_string(config: Config, key: String) -> Result(String, Nil) {
  case get(config, key) {
    Ok(StringVal(s)) -> Ok(s)
    _ -> Error(Nil)
  }
}

pub fn get_int(config: Config, key: String) -> Result(Int, Nil) {
  case get(config, key) {
    Ok(IntVal(n)) -> Ok(n)
    _ -> Error(Nil)
  }
}

pub fn get_bool(config: Config, key: String) -> Result(Bool, Nil) {
  case get(config, key) {
    Ok(BoolVal(b)) -> Ok(b)
    _ -> Error(Nil)
  }
}
