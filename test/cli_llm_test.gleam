import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/string
import gleamunison/cli_llm
import gleamunison/llm.{Completion}

fn fake_env(pairs: List(#(String, String))) -> fn(String) -> Result(String, Nil) {
  fn(key) {
    case list_find(pairs, key) {
      Ok(v) -> Ok(v)
      Error(_) -> Error(Nil)
    }
  }
}

fn list_find(pairs: List(#(String, String)), key: String) -> Result(String, Nil) {
  case pairs {
    [] -> Error(Nil)
    [#(k, v), ..rest] ->
      case k == key {
        True -> Ok(v)
        False -> list_find(rest, key)
      }
  }
}

pub fn resolve_config_openai_defaults_test() {
  let env = fake_env([#("OPENAI_API_KEY", "sk-live")])
  let assert Ok(cfg) = cli_llm.resolve_config(llm.OpenAI, env)
  let assert True = cfg.api_key == "sk-live"
  let assert True = cfg.base_url == "https://api.openai.com/v1"
  let assert True = cfg.model == "gpt-4o-mini"
  let assert True = cfg.max_tokens == 4096
}

pub fn resolve_config_honours_env_overrides_test() {
  let env =
    fake_env([
      #("OPENAI_API_KEY", "sk-x"),
      #("OPENAI_MODEL", "gpt-5"),
      #("OPENAI_BASE_URL", "http://localhost:11434/v1"),
    ])
  let assert Ok(cfg) = cli_llm.resolve_config(llm.OpenAI, env)
  let assert True = cfg.model == "gpt-5"
  let assert True = cfg.base_url == "http://localhost:11434/v1"
}

pub fn resolve_config_missing_key_is_clear_error_test() {
  let env = fake_env([])
  let assert Error(msg) = cli_llm.resolve_config(llm.Anthropic, env)
  let assert True = string.contains(msg, "ANTHROPIC_API_KEY")
}

pub fn default_provider_prefers_anthropic_when_key_present_test() {
  let env =
    fake_env([#("OPENAI_API_KEY", "sk"), #("ANTHROPIC_API_KEY", "sk-ant")])
  let assert True = cli_llm.default_provider(env) == llm.Anthropic
  let env2 = fake_env([#("OPENAI_API_KEY", "sk")])
  let assert True = cli_llm.default_provider(env2) == llm.OpenAI
}

pub fn complete_with_mock_returns_completion_test() {
  let handler =
    llm.mock_handler(Completion("hello back", "mock-model", 3, 7))
  let assert Ok(c) = cli_llm.complete_with(handler, "hi")
  let assert True = c.content == "hello back"
  let assert True = c.model == "mock-model"
  let assert True = c.output_tokens == 7
}

pub fn complete_with_surfaces_handler_error_test() {
  let handler = fn(_args, cont) {
    cont(cast_error("quota exhausted"))
  }
  let assert Error(msg) = cli_llm.complete_with(handler, "hi")
  let assert True = string.contains(msg, "quota exhausted")
}

pub fn command_with_handler_end_to_end_test() {
  let handler =
    llm.mock_handler(Completion("it works", "mock-1", 1, 2))
  let env = fake_env([#("ANTHROPIC_API_KEY", "sk-ant")])
  let out = cli_llm.command_with_handler(["anthropic", "say hi"], env, handler)
  let assert True = string.contains(out, "it works")
}

pub fn command_usage_on_empty_args_test() {
  let env = fake_env([])
  let out =
    cli_llm.command_with_handler(
      [],
      env,
      llm.mock_handler(Completion("x", "m", 0, 0)),
    )
  let assert True = string.contains(out, "usage")
}

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn cast_any(a: anything) -> Dynamic

fn cast_error(msg: String) -> Dynamic {
  cast_any(Error(bit_array.from_string(msg)))
}
