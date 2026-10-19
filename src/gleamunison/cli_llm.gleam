//// `gleamunison llm` — the LLM ability reachable from the shipped binary.
////
//// Env lookup and the op handler are both injected, so the live provider,
//// a retry-wrapped provider, and a test mock are the same function call.
//// That swap is the entire point of the ability design.

import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/result
import gleamunison/effects.{type OpHandler}
import gleamunison/json
import gleamunison/llm.{
  type Completion, type Provider, type ProviderConfig, Anthropic, Completion,
  Message, OpenAI, User,
}
import gleamunison/llm_middleware.{RetryPolicy}

@external(erlang, "gleamunison_config", "get_env")
fn ffi_get_env(key: String) -> Result(String, Nil)

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn cast(a: anything) -> Dynamic

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn uncast(a: Dynamic) -> anything

pub type EnvLookup =
  fn(String) -> Result(String, Nil)

/// CLI entry: `gleam run -- llm [openai|anthropic] <prompt>`.
pub fn command(args: List(String)) -> String {
  command_with_env(args, ffi_get_env)
}

pub fn command_with_env(args: List(String), env: EnvLookup) -> String {
  case command_result_with_env(args, env) {
    Ok(message) | Error(message) -> message
  }
}

/// The process boundary must not guess success from the rendered text.
pub fn command_result(args: List(String)) -> Result(String, String) {
  command_result_with_env(args, ffi_get_env)
}

fn command_result_with_env(
  args: List(String),
  env: EnvLookup,
) -> Result(String, String) {
  use #(provider, prompt) <- result.try(parse_args(args, env))
  use cfg <- result.try(resolve_config(provider, env))
  command_with_handler_cfg(cfg, prompt)
}

/// Test seam: same pipeline with the handler swapped in.
pub fn command_with_handler(
  args: List(String),
  env: EnvLookup,
  handler: OpHandler,
) -> String {
  case parse_args(args, env) {
    Error(msg) -> msg
    Ok(#(_provider, prompt)) -> format_result(complete_with(handler, prompt))
  }
}

fn command_with_handler_cfg(
  cfg: ProviderConfig,
  prompt: String,
) -> Result(String, String) {
  let handler =
    llm_middleware.retry_handler(
      llm.provider_handler(cfg),
      RetryPolicy(max_attempts: 3, base_delay_ms: 500),
    )
  complete_with(handler, prompt) |> result.map(fn(c) { format_result(Ok(c)) })
}

fn parse_args(
  args: List(String),
  env: EnvLookup,
) -> Result(#(Provider, String), String) {
  case args {
    [] -> Error(usage())
    [prompt] -> Ok(#(default_provider(env), prompt))
    [flag, prompt] ->
      case provider_flag(flag) {
        Ok(p) -> Ok(#(p, prompt))
        Error(_) -> Error(usage())
      }
    _ -> Error(usage())
  }
}

fn usage() -> String {
  "usage: gleam run -- llm [openai|anthropic] <prompt>"
}

fn provider_flag(flag: String) -> Result(Provider, Nil) {
  case flag {
    "openai" -> Ok(OpenAI)
    "anthropic" -> Ok(Anthropic)
    _ -> Error(Nil)
  }
}

/// Which provider to call when the user did not say: Anthropic if its key
/// exists, else OpenAI.
pub fn default_provider(env: EnvLookup) -> Provider {
  case env("ANTHROPIC_API_KEY") {
    Ok(_) -> Anthropic
    Error(_) -> OpenAI
  }
}

/// Provider config from the environment, with sane defaults.
pub fn resolve_config(
  provider: Provider,
  env: EnvLookup,
) -> Result(ProviderConfig, String) {
  llm.resolve_config(provider, env)
}

/// Drive any LLM op handler with a single user prompt. The handler decides
/// what that means — live HTTP, retry, mock; this function only moves data.
pub fn complete_with(
  handler: OpHandler,
  prompt: String,
) -> Result(Completion, String) {
  let body = llm.messages_json([Message(User, prompt)])
  let arg = cast(bit_array.from_string(body))
  let result: Result(BitArray, BitArray) = uncast(handler([arg], identity))
  case result {
    Error(e) -> Error("llm: " <> unwrap_bit(e))
    Ok(bin) ->
      case json.decode(bin) {
        Error(_) -> Error("llm: undecodable completion payload")
        Ok(dyn) ->
          case decode.run(dyn, completion_decoder()) {
            Ok(c) -> Ok(c)
            Error(_) -> Error("llm: completion shape mismatch")
          }
      }
  }
}

fn identity(d: Dynamic) -> Dynamic {
  d
}

fn completion_decoder() -> decode.Decoder(Completion) {
  use content <- decode.field("content", decode.string)
  use model <- decode.field("model", decode.string)
  use input_tokens <- decode.field("input_tokens", decode.int)
  use output_tokens <- decode.field("output_tokens", decode.int)
  decode.success(Completion(content, model, input_tokens, output_tokens))
}

fn format_result(r: Result(Completion, String)) -> String {
  case r {
    Error(msg) -> msg
    Ok(c) ->
      c.content
      <> "\n\n— "
      <> c.model
      <> " ("
      <> int.to_string(c.input_tokens)
      <> " in / "
      <> int.to_string(c.output_tokens)
      <> " out)"
  }
}

fn unwrap_bit(b: BitArray) -> String {
  case bit_array.to_string(b) {
    Ok(s) -> s
    Error(_) -> "<non-utf8>"
  }
}
