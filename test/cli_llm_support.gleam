//// Test-side CLI LLM seams (bk-15d8): the handler-swap pipeline entry,
//// provider defaulting, and bare completion drive had no production
//// callers — production routes through command_result → resolve_config →
//// retry-wrapped provider handler. The module doc's own promise ("the
//// live provider, a retry-wrapped provider, and a test mock are the same
//// function call") is exercised from test/; these are its test-side
//// halves, shape-identical to what used to live in src.

import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleamunison/cli_llm
import gleamunison/dynamic_ffi.{from_dynamic, to_dynamic}
import gleamunison/effects.{type OpHandler}
import gleamunison/json
import gleamunison/llm_types.{type Completion, type Provider, Message, User}
import gleamunison/llm_wire

/// Same pipeline as cli_llm.command_result with the op handler swapped in:
/// parse, then complete, then render.
pub fn command_with_handler(
  args: List(String),
  env: cli_llm.EnvLookup,
  handler: OpHandler,
) -> String {
  case parse_args(args, env) {
    Error(msg) -> msg
    Ok(#(_provider, prompt)) -> format_result(complete_with(handler, prompt))
  }
}

/// Which provider to call when the user did not say: Anthropic if its key
/// exists, else OpenAI.
pub fn default_provider(env: cli_llm.EnvLookup) -> Provider {
  case env("ANTHROPIC_API_KEY") {
    Ok(_) -> llm_types.Anthropic
    Error(_) -> llm_types.OpenAI
  }
}

/// Drive any LLM op handler with a single user prompt. The handler decides
/// what that means — live HTTP, retry, mock; this function only moves data.
pub fn complete_with(
  handler: OpHandler,
  prompt: String,
) -> Result(Completion, String) {
  let body = llm_wire.messages_json([Message(User, prompt)])
  let arg = to_dynamic(bit_array.from_string(body))
  let result: Result(BitArray, BitArray) =
    from_dynamic(handler([arg], identity))
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

fn parse_args(
  args: List(String),
  env: cli_llm.EnvLookup,
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
    "openai" -> Ok(llm_types.OpenAI)
    "anthropic" -> Ok(llm_types.Anthropic)
    _ -> Error(Nil)
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
  decode.success(llm_types.Completion(
    content,
    model,
    input_tokens,
    output_tokens,
  ))
}

fn format_result(r: Result(Completion, String)) -> String {
  case r {
    Error(msg) -> msg
    Ok(c) ->
      c.content
      <> "\n\n— "
      <> c.model
      <> " ("
      <> int_to_string(c.input_tokens)
      <> " in / "
      <> int_to_string(c.output_tokens)
      <> " out)"
  }
}

fn int_to_string(n: Int) -> String {
  int.to_string(n)
}

fn unwrap_bit(b: BitArray) -> String {
  case bit_array.to_string(b) {
    Ok(s) -> s
    Error(_) -> "<non-utf8>"
  }
}
