//// LLM ability host surface (gap analysis concept A).
////
//// The LLM call is an effect; providers, retries, fallbacks, and mocks are
//// composable handlers over the effects.run stack — no client registry, no
//// codegen. Op contract at the handler boundary:
////   args[0] = messages JSON BitArray ([{"role":"user","content":"..."}])
////   result passed to continuation = {ok, CompletionJsonBin} | {error, ReasonBin}
////
//// The provider wire codec (request building, response parsing, house
//// completion shape) lives in gleamunison/llm_wire; this module owns the
//// ability host surface.

import gleam/bit_array
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/option.{type Option, None}
import gleam/result
import gleamunison/cancellation
import gleamunison/effects.{type HandlerFrame, type OpHandler, HandlerFrame}
import gleamunison/http_client
import gleamunison/identity.{type DefinitionRef, Ref}
import gleamunison/json
import gleamunison/llm_budget
import gleamunison/llm_controls
import gleamunison/llm_types.{
  type Completion, type LlmError, type Message, type Provider,
  type ProviderConfig, type Role, Anthropic, Assistant, Completion, DecodeError,
  HttpError, Message, OpenAI, ProviderConfig, System, TransportError, User,
}
import gleamunison/llm_wire

@external(erlang, "gleamunison_config", "get_env")
fn get_env(key: String) -> Result(String, Nil)

@external(erlang, "gleamunison_ffi", "from_dynamic")
fn unsafe_coerce(val: Dynamic) -> a

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn to_dynamic(val: a) -> Dynamic

pub fn ability_ref() -> DefinitionRef {
  // Abilities resolve by name hash (same rule as elaborate.ref_for_name):
  // surface `(do LLM ...)` compiles against this ref, so handler frames
  // keyed here actually dispatch. The genesis ordinal ref was a mismatch.
  Ref(identity.hash_bytes(<<"LLM">>))
}

pub fn provider_name(provider: Provider) -> String {
  case provider {
    Anthropic -> "anthropic"
    OpenAI -> "openai"
  }
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
      let provider_name = provider_name(provider)
      // Budget/circuit gate: admission, concurrency slot, and metering are
      // owned by gleamunison_llm_budget; refusal names are typed policy.
      use Nil <- result.try(budget_admit(provider_name, cfg.model))
      let body = llm_wire.messages_json([Message(User, prompt)])
      let result: Result(BitArray, BitArray) =
        unsafe_coerce(
          provider_handler(cfg)(
            [to_dynamic(bit_array.from_string(body))],
            fn(d) { d },
          ),
        )
      let completion = case result {
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
              case decode.run(dyn, llm_wire.completion_decoder()) {
                Ok(c) -> Ok(c)
                Error(_) -> Error("llm: completion shape mismatch")
              }
          }
      }
      // Release the concurrency slot exactly once, then meter and report.
      let assert Ok(Nil) = budget_release(provider_name)
      case completion {
        Ok(c) -> {
          let rates = rate_config(get_env)
          let cost =
            llm_budget.cost_micro_usd(
              c.input_tokens,
              c.output_tokens,
              rates.0,
              rates.1,
            )
          let assert Ok(Nil) =
            budget_spend(provider_name, c.input_tokens + c.output_tokens, cost)
          let assert Ok(Nil) = budget_report_success(provider_name)
          Ok(c.content)
        }
        Error(msg) -> {
          let assert Ok(Nil) = budget_report_failure(provider_name)
          Error(msg)
        }
      }
    }
  }
}

@external(erlang, "gleamunison_llm_budget", "admit")
fn budget_admit(provider: String, model: String) -> Result(Nil, String)

@external(erlang, "gleamunison_llm_budget", "release")
fn budget_release(provider: String) -> Result(Nil, Nil)

@external(erlang, "gleamunison_llm_budget", "spend")
fn budget_spend(
  provider: String,
  tokens: Int,
  cost_micro_usd: Int,
) -> Result(Nil, Nil)

@external(erlang, "gleamunison_llm_budget", "report_success")
fn budget_report_success(provider: String) -> Result(Nil, Nil)

@external(erlang, "gleamunison_llm_budget", "report_failure")
fn budget_report_failure(provider: String) -> Result(Nil, Nil)

/// Rates are data, not policy: micro-USD per 1M tokens from the environment,
/// defaulting to zero (metering on, cost accounting estimate-only).
fn rate_config(env: llm_controls.EnvLookup) -> #(Int, Int) {
  let prompt_rate =
    llm_controls.env_or(env, "GLEAMUNISON_LLM_PROMPT_RATE_MICRO_USD", "0")
  let completion_rate =
    llm_controls.env_or(env, "GLEAMUNISON_LLM_COMPLETION_RATE_MICRO_USD", "0")
  #(parse_non_negative(prompt_rate), parse_non_negative(completion_rate))
}

fn parse_non_negative(text: String) -> Int {
  case int.parse(text) {
    Ok(n) if n >= 0 -> n
    _ -> 0
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

/// Wrap any LLM OpHandler as a HandlerFrame for effects.run.
pub fn frame(handler: OpHandler) -> HandlerFrame {
  HandlerFrame(ability: ability_ref(), ops: dict.from_list([#(0, handler)]))
}

// ---------------------------------------------------------------------------
// Handlers

/// Deterministic mock: always answers the same completion. The live call and
/// the test double are the same handler swap — that is the whole point.
pub fn mock_handler(response: Completion) -> OpHandler {
  fn(_args: List(Dynamic), cont: fn(Dynamic) -> Dynamic) -> Dynamic {
    cont(to_dynamic(Ok(llm_wire.completion_json(response))))
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
            Error(e) ->
              Error(DecodeError("messages json: " <> llm_wire.unwrap_bit(e)))
            Ok(dyn) -> {
              case decode.run(dyn, decode.list(llm_wire.message_decoder())) {
                Error(_) -> Error(DecodeError("messages shape mismatch"))
                Ok(msgs) -> {
                  let #(url, headers, body) = llm_wire.build_request(cfg, msgs)
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
                      let body_str = llm_wire.unwrap_bit(http_client.body(resp))
                      case
                        llm_wire.parse_response(
                          cfg.provider,
                          http_client.status(resp),
                          body_str,
                        )
                      {
                        Ok(c) -> Ok(llm_wire.completion_json(c))
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

pub fn error_string(e: LlmError) -> String {
  case e {
    TransportError(r) -> "transport: " <> r
    HttpError(status, body) -> "http " <> int.to_string(status) <> ": " <> body
    DecodeError(r) -> "decode: " <> r
  }
}
