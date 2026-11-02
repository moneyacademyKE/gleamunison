//// `gleamunison llm` — the LLM ability reachable from the shipped binary.
////
//// Env lookup and the op handler are both injected, so the live provider,
//// a retry-wrapped provider, and a test mock are the same function call.
//// That swap is the entire point of the ability design.

import gleam/bit_array
import gleam/dynamic/decode
import gleam/int
import gleam/result
import gleamunison/dynamic_ffi.{from_dynamic, to_dynamic}
import gleamunison/env
import gleamunison/json
import gleamunison/llm
import gleamunison/llm_middleware.{RetryPolicy}
import gleamunison/llm_types.{
  type Completion, type Provider, type ProviderConfig, Anthropic, Completion,
  Message, OpenAI, User,
}
import gleamunison/llm_wire

pub type EnvLookup =
  fn(String) -> Result(String, Nil)

/// CLI entry: `gleam run -- llm [openai|anthropic] <prompt>`.
pub fn command(args: List(String)) -> String {
  command_with_env(args, env.get)
}

fn command_with_env(args: List(String), env: EnvLookup) -> String {
  case command_result_with_env(args, env) {
    Ok(message) | Error(message) -> message
  }
}

/// The process boundary must not guess success from the rendered text.
pub fn command_result(args: List(String)) -> Result(String, String) {
  command_result_with_env(args, env.get)
}

fn command_result_with_env(
  args: List(String),
  env: EnvLookup,
) -> Result(String, String) {
  use #(provider, prompt) <- result.try(parse_args(args, env))
  use cfg <- result.try(resolve_config(provider, env))
  command_with_handler_cfg(cfg, prompt)
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
  let body = llm_wire.messages_json([Message(User, prompt)])
  let arg = to_dynamic(bit_array.from_string(body))
  let result: Result(BitArray, BitArray) =
    from_dynamic(handler([arg], fn(d) { d }))
  let completion = case result {
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
  completion |> result.map(fn(c) { format_result(Ok(c)) })
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
fn default_provider(env: EnvLookup) -> Provider {
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
