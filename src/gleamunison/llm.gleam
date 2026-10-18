//// LLM ability host surface (gap analysis concept A).
////
//// The LLM call is an effect; providers, retries, fallbacks, and mocks are
//// composable handlers over the effects.run stack — no client registry, no
//// codegen. Op contract at the handler boundary:
////   args[0] = messages JSON BitArray ([{"role":"user","content":"..."}])
////   result passed to continuation = {ok, CompletionJsonBin} | {error, ReasonBin}

import gleam/bit_array
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{type Option, None}
import gleam/result
import gleam/string
import gleamunison/cancellation
import gleamunison/effects.{type HandlerFrame, type OpHandler, HandlerFrame}
import gleamunison/http_client
import gleamunison/identity.{type DefinitionRef, Ref}
import gleamunison/json
import gleamunison/llm_controls

@external(erlang, "gleamunison_config", "get_env")
fn get_env(key: String) -> Result(String, Nil)

@external(erlang, "gleamunison_ffi", "from_dynamic")
fn unsafe_coerce(val: Dynamic) -> a

pub type Role {
  System
  User
  Assistant
}

pub type Message {
  Message(role: Role, content: String)
}

pub type Completion {
  Completion(
    content: String,
    model: String,
    input_tokens: Int,
    output_tokens: Int,
  )
}

pub type LlmError {
  TransportError(reason: String)
  HttpError(status: Int, body: String)
  DecodeError(reason: String)
}

pub type Provider {
  OpenAI
  Anthropic
}

pub type ProviderConfig {
  ProviderConfig(
    provider: Provider,
    base_url: String,
    api_key: String,
    model: String,
    max_tokens: Int,
    timeout_ms: Int,
    /// OpenAI-compatible reasoning effort ("low"/"medium"/"high"/"max").
    /// Empty string = omit from the request (provider default).
    reasoning_effort: String,
  )
}

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn to_dynamic(val: a) -> Dynamic

pub fn ability_ref() -> DefinitionRef {
  // Abilities resolve by name hash (same rule as elaborate.ref_for_name):
  // surface `(do LLM ...)` compiles against this ref, so handler frames
  // keyed here actually dispatch. The genesis ordinal ref was a mismatch.
  Ref(identity.hash_bytes(<<"LLM">>))
}

/// One-shot completion from environment config: the default live handler
/// body. Reads OPENAI_API_KEY/OPENAI_BASE_URL/OPENAI_MODEL (or ANTHROPIC_*
/// when its key is set). Kept dependency-free so the Erlang runtime can
/// call it directly as the ambient handler.
pub fn complete_env(prompt: String) -> Result(String, String) {
  let provider = case get_env("ANTHROPIC_API_KEY") {
    Ok(_) -> Anthropic
    Error(_) -> OpenAI
  }
  case resolve_config(provider, get_env) {
    Error(error) -> Error(error)
    Ok(cfg) -> {
      let body = messages_json([Message(User, prompt)])
      let result: Result(BitArray, BitArray) =
        unsafe_coerce(
          provider_handler(cfg)(
            [to_dynamic(bit_array.from_string(body))],
            fn(d) { d },
          ),
        )
      case result {
        Error(e) ->
          Error(
            "llm: "
            <> case bit_array.to_string(e) {
              Ok(s) -> s
              Error(_) -> "<non-utf8>"
            },
          )
        Ok(bin) ->
          case json.decode(bin) {
            Error(_) -> Error("llm: undecodable completion payload")
            Ok(dyn) ->
              case decode.run(dyn, env_completion_decoder()) {
                Ok(c) -> Ok(c.content)
                Error(_) -> Error("llm: completion shape mismatch")
              }
          }
      }
    }
  }
}

/// Resolve both CLI and ambient settings without silently accepting bad values.
pub fn resolve_config(
  provider: Provider,
  env: llm_controls.EnvLookup,
) -> Result(ProviderConfig, String) {
  use #(url, key, model, tokens, timeout_ms, effort) <- result.try(
    llm_controls.resolve(provider == Anthropic, env),
  )
  Ok(ProviderConfig(provider, url, key, model, tokens, timeout_ms, effort))
}

pub fn validate_config(cfg: ProviderConfig) -> Result(Nil, String) {
  llm_controls.validate(
    cfg.provider == Anthropic,
    cfg.base_url,
    cfg.api_key,
    cfg.model,
    cfg.max_tokens,
    cfg.timeout_ms,
    cfg.reasoning_effort,
  )
}

fn env_completion_decoder() -> decode.Decoder(Completion) {
  use content <- decode.field("content", decode.string)
  use model <- decode.field("model", decode.string)
  use input_tokens <- decode.field("input_tokens", decode.int)
  use output_tokens <- decode.field("output_tokens", decode.int)
  decode.success(Completion(content, model, input_tokens, output_tokens))
}

/// Wrap any LLM OpHandler as a HandlerFrame for effects.run.
pub fn frame(handler: OpHandler) -> HandlerFrame {
  HandlerFrame(ability: ability_ref(), ops: dict.from_list([#(0, handler)]))
}

// ---------------------------------------------------------------------------
// Request building (pure)

pub fn build_request(
  cfg: ProviderConfig,
  messages: List(Message),
) -> #(String, List(#(String, String)), String) {
  let effort_field = case cfg.reasoning_effort {
    "" -> ""
    e -> ",\"reasoning_effort\":" <> jstr(e)
  }
  case cfg.provider {
    OpenAI -> #(
      cfg.base_url <> "/chat/completions",
      [
        #("authorization", "Bearer " <> cfg.api_key),
        #("content-type", "application/json"),
      ],
      "{\"model\":"
        <> jstr(cfg.model)
        <> ",\"max_tokens\":"
        <> int.to_string(cfg.max_tokens)
        <> effort_field
        <> ",\"messages\":"
        <> messages_json(messages)
        <> "}",
    )
    Anthropic -> {
      let #(system, rest) = list.partition(messages, fn(m) { m.role == System })
      let system_field = case system {
        [] -> ""
        sys -> "\"system\":" <> jstr(join_contents(sys)) <> ","
      }
      #(
        cfg.base_url <> "/v1/messages",
        [
          #("x-api-key", cfg.api_key),
          #("anthropic-version", "2023-06-01"),
          #("content-type", "application/json"),
        ],
        "{\"model\":"
          <> jstr(cfg.model)
          <> ",\"max_tokens\":"
          <> int.to_string(cfg.max_tokens)
          <> ","
          <> system_field
          <> "\"messages\":"
          <> messages_json(rest)
          <> "}",
      )
    }
  }
}

fn join_contents(msgs: List(Message)) -> String {
  msgs
  |> list.map(fn(m) { m.content })
  |> string.join("\n")
}

pub fn messages_json(msgs: List(Message)) -> String {
  let parts =
    list.map(msgs, fn(m) {
      "{\"role\":"
      <> jstr(role_name(m.role))
      <> ",\"content\":"
      <> jstr(m.content)
      <> "}"
    })
  "[" <> string.join(parts, ",") <> "]"
}

fn role_name(r: Role) -> String {
  case r {
    System -> "system"
    User -> "user"
    Assistant -> "assistant"
  }
}

fn jstr(s: String) -> String {
  "\"" <> escape(s) <> "\""
}

fn escape(s: String) -> String {
  s
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
  |> string.replace("\t", "\\t")
}

// ---------------------------------------------------------------------------
// Response parsing (pure)

pub fn parse_response(
  provider: Provider,
  status: Int,
  body: String,
) -> Result(Completion, LlmError) {
  case status >= 200 && status < 300 {
    False -> Error(HttpError(status, "provider_error_body_omitted"))
    True -> {
      case json.decode(bit_array.from_string(body)) {
        Error(e) -> Error(DecodeError("json: " <> unwrap_bit(e)))
        Ok(dyn) -> {
          let decoder = case provider {
            OpenAI -> openai_decoder()
            Anthropic -> anthropic_decoder()
          }
          case decode.run(dyn, decoder) {
            Ok(c) -> Ok(c)
            Error(_) -> Error(DecodeError("response shape mismatch"))
          }
        }
      }
    }
  }
}

fn unwrap_bit(b: BitArray) -> String {
  case bit_array.to_string(b) {
    Ok(s) -> s
    Error(_) -> "<non-utf8>"
  }
}

fn openai_decoder() -> decode.Decoder(Completion) {
  let content_decoder =
    decode.field(
      "message",
      decode.field("content", decode.string, decode.success),
      decode.success,
    )
  use choices <- decode.field("choices", decode.list(content_decoder))
  use model <- decode.field("model", decode.string)
  use usage <- decode.field("usage", {
    use p <- decode.field("prompt_tokens", decode.int)
    use c <- decode.field("completion_tokens", decode.int)
    decode.success(#(p, c))
  })
  case list.first(choices) {
    Ok(content) -> decode.success(Completion(content, model, usage.0, usage.1))
    Error(_) -> decode.failure(Completion("", "", 0, 0), "non-empty choices")
  }
}

fn anthropic_decoder() -> decode.Decoder(Completion) {
  let text_decoder = decode.field("text", decode.string, decode.success)
  use parts <- decode.field("content", decode.list(text_decoder))
  use model <- decode.field("model", decode.string)
  use usage <- decode.field("usage", {
    use i <- decode.field("input_tokens", decode.int)
    use o <- decode.field("output_tokens", decode.int)
    decode.success(#(i, o))
  })
  case list.first(parts) {
    Ok(content) -> decode.success(Completion(content, model, usage.0, usage.1))
    Error(_) -> decode.failure(Completion("", "", 0, 0), "non-empty content")
  }
}

// ---------------------------------------------------------------------------
// Handlers

pub fn completion_json(c: Completion) -> BitArray {
  bit_array.from_string(
    "{\"content\":"
    <> jstr(c.content)
    <> ",\"model\":"
    <> jstr(c.model)
    <> ",\"input_tokens\":"
    <> int.to_string(c.input_tokens)
    <> ",\"output_tokens\":"
    <> int.to_string(c.output_tokens)
    <> "}",
  )
}

/// Deterministic mock: always answers the same completion. The live call and
/// the test double are the same handler swap — that is the whole point.
pub fn mock_handler(response: Completion) -> OpHandler {
  fn(_args: List(Dynamic), cont: fn(Dynamic) -> Dynamic) -> Dynamic {
    cont(to_dynamic(Ok(completion_json(response))))
  }
}

/// Live provider handler: performs the HTTP call via http_client.
pub fn provider_handler(cfg: ProviderConfig) -> OpHandler {
  provider_handler_with_cancellation(cfg, None)
}

/// Build a live handler with an optional caller-owned cancellation token.
pub fn provider_handler_with_cancellation(
  cfg: ProviderConfig,
  cancellation: Option(cancellation.Token),
) -> OpHandler {
  fn(args: List(Dynamic), cont: fn(Dynamic) -> Dynamic) -> Dynamic {
    cont(case validate_config(cfg) {
      Error(reason) -> to_dynamic(Error(bit_array.from_string(reason)))
      Ok(Nil) ->
        case perform(cfg, args, cancellation) {
          Ok(json_bin) -> to_dynamic(Ok(json_bin))
          Error(e) -> to_dynamic(Error(bit_array.from_string(error_string(e))))
        }
    })
  }
}

fn perform(
  cfg: ProviderConfig,
  args: List(Dynamic),
  cancellation: Option(cancellation.Token),
) -> Result(BitArray, LlmError) {
  case args {
    [messages_dyn, ..] -> {
      case decode.run(messages_dyn, decode.bit_array) {
        Error(_) -> Error(DecodeError("args[0] must be a JSON bit array"))
        Ok(bin) -> {
          case json.decode(bin) {
            Error(e) -> Error(DecodeError("messages json: " <> unwrap_bit(e)))
            Ok(dyn) -> {
              case decode.run(dyn, decode.list(message_decoder())) {
                Error(_) -> Error(DecodeError("messages shape mismatch"))
                Ok(msgs) -> {
                  let #(url, headers, body) = build_request(cfg, msgs)
                  case
                    http_client.request_with_options(
                      "POST",
                      url,
                      headers,
                      bit_array.from_string(body),
                      cfg.timeout_ms,
                      cancellation,
                    )
                  {
                    Error(http_client.HttpError(reason)) ->
                      Error(TransportError(reason))
                    Ok(resp) -> {
                      let body_str = unwrap_bit(http_client.body(resp))
                      case
                        parse_response(
                          cfg.provider,
                          http_client.status(resp),
                          body_str,
                        )
                      {
                        Ok(c) -> Ok(completion_json(c))
                        Error(e) -> Error(e)
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    [] -> Error(DecodeError("llm_complete expects messages argument"))
  }
}

fn message_decoder() -> decode.Decoder(Message) {
  use role <- decode.field("role", decode.string)
  use content <- decode.field("content", decode.string)
  case role {
    "system" -> decode.success(Message(System, content))
    "user" -> decode.success(Message(User, content))
    "assistant" -> decode.success(Message(Assistant, content))
    other -> decode.failure(Message(User, ""), "known role, got " <> other)
  }
}

pub fn error_string(e: LlmError) -> String {
  case e {
    TransportError(r) -> "transport: " <> r
    HttpError(status, body) -> "http " <> int.to_string(status) <> ": " <> body
    DecodeError(r) -> "decode: " <> r
  }
}
