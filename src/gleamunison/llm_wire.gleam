//// Provider wire codec for the LLM ability (pure data <-> JSON).
////
//// One owner for the provider wire format: request building, response
//// parsing, JSON string escaping, and the house completion shape. Split
//// from llm.gleam so each module keeps exactly one concern — llm.gleam
//// owns the ability host surface (handlers, budget gate, config), this
//// module owns the wire.

import gleam/bit_array
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/string
import gleamunison/json
import gleamunison/llm_types.{
  type Completion, type LlmError, type Message, type Provider,
  type ProviderConfig, type Role, Anthropic, Assistant, Completion, DecodeError,
  HttpError, Message, OpenAI, System, User,
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

pub fn unwrap_bit(b: BitArray) -> String {
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
// House completion shape

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

/// Decoder for the house completion shape — what completion_json emits and
/// mocks return. Provider wire bodies go through parse_response instead.
pub fn completion_decoder() -> decode.Decoder(Completion) {
  use content <- decode.field("content", decode.string)
  use model <- decode.field("model", decode.string)
  use input <- decode.field("input_tokens", decode.int)
  use output <- decode.field("output_tokens", decode.int)
  decode.success(Completion(content, model, input, output))
}

pub fn message_decoder() -> decode.Decoder(Message) {
  use role <- decode.field("role", decode.string)
  use content <- decode.field("content", decode.string)
  case role {
    "system" -> decode.success(Message(System, content))
    "user" -> decode.success(Message(User, content))
    "assistant" -> decode.success(Message(Assistant, content))
    other -> decode.failure(Message(User, ""), "known role, got " <> other)
  }
}
