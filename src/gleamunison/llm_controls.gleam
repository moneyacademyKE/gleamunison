//// Primitive controls shared by ambient/CLI provider configuration and
//// retry composition. No provider registry or dependency on llm types.

import gleam/bit_array
import gleam/int
import gleam/list
import gleam/result
import gleam/string

const default_timeout_ms = 180_000

pub type EnvLookup =
  fn(String) -> Result(String, Nil)

@external(erlang, "gleamunison_llm_controls", "safe_url")
fn safe_url(url: String) -> Bool

pub fn resolve(
  anthropic: Bool,
  env: EnvLookup,
) -> Result(#(String, String, String, Int, Int, String), String) {
  let #(key_var, url_var, model_var, url_default, model_default) = case
    anthropic
  {
    True -> #(
      "ANTHROPIC_API_KEY",
      "ANTHROPIC_BASE_URL",
      "ANTHROPIC_MODEL",
      "https://api.anthropic.com",
      "claude-haiku-4-5",
    )
    False -> #(
      "OPENAI_API_KEY",
      "OPENAI_BASE_URL",
      "OPENAI_MODEL",
      "https://api.openai.com/v1",
      "gpt-4o-mini",
    )
  }
  use key <- result.try(
    env(key_var)
    |> result.replace_error("llm: missing " <> key_var <> " in environment"),
  )
  let effort = env_or(env, "LLM_REASONING_EFFORT", "")
  let default_tokens = case effort {
    "" -> "4096"
    _ -> "16384"
  }
  use tokens <- result.try(
    int.parse(env_or(env, "LLM_MAX_TOKENS", default_tokens))
    |> result.replace_error("settings: invalid LLM_MAX_TOKENS"),
  )
  let url = env_or(env, url_var, url_default)
  let model = env_or(env, model_var, model_default)
  let timeout_text =
    env_or(env, "LLM_HTTP_TIMEOUT_MS", int.to_string(default_timeout_ms))
  use timeout_ms <- result.try(
    int.parse(timeout_text)
    |> result.replace_error("settings: invalid LLM_HTTP_TIMEOUT_MS"),
  )
  use Nil <- result.try(validate(
    anthropic,
    url,
    key,
    model,
    tokens,
    timeout_ms,
    effort,
  ))
  Ok(#(url, key, model, tokens, timeout_ms, effort))
}

pub fn validate(
  anthropic: Bool,
  url: String,
  key: String,
  model: String,
  tokens: Int,
  timeout_ms: Int,
  effort: String,
) -> Result(Nil, String) {
  case
    tokens < 1 || tokens > 131_072 || timeout_ms < 1 || timeout_ms > 180_000
  {
    True -> Error("settings: max_tokens and timeout must be within bounds")
    False ->
      case !list.contains(["", "low", "medium", "high", "max"], effort) {
        True -> Error("settings: unsupported reasoning effort")
        False ->
          case anthropic && effort != "" {
            True -> Error("settings: Anthropic reasoning_effort is unsupported")
            False ->
              case !safe_text(key, 4096) || !safe_text(model, 256) {
                True -> Error("settings: invalid credential or model")
                False ->
                  case safe_url(url) {
                    True -> Ok(Nil)
                    False ->
                      Error(
                        "settings: provider URL must be HTTPS or loopback HTTP",
                      )
                  }
              }
          }
      }
  }
}

fn safe_text(value: String, limit: Int) -> Bool {
  value != ""
  && string.byte_size(value) <= limit
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
  && !string.contains(value, "\u{0}")
}

pub fn env_or(env: EnvLookup, key: String, fallback: String) -> String {
  case env(key) {
    Ok(value) -> value
    Error(_) -> fallback
  }
}

pub fn attempts(value: Int) -> Int {
  case value {
    n if n < 1 -> 1
    n if n > 3 -> 3
    n -> n
  }
}

pub fn retry_delay(base: Int, attempt: Int) -> Int {
  case base {
    n if n <= 0 -> 0
    n if n > 1000 -> 1000
    n ->
      case n * attempt {
        delay if delay > 1000 -> 1000
        delay -> delay
      }
  }
}

pub fn retryable(reason: BitArray) -> Bool {
  case bit_array.to_string(reason) {
    Error(_) -> False
    Ok(text) ->
      !list.any(
        [
          "cancelled",
          "settings:",
          "decode:",
          "http 400",
          "http 401",
          "http 403",
          "http 404",
          "http 422",
        ],
        fn(prefix) { string.starts_with(text, prefix) },
      )
  }
}
