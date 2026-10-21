import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/string
import gleamunison/llm
import gleamunison/llm_types.{
  type ProviderConfig, Anthropic, Completion, Message, OpenAI, ProviderConfig,
  System, User,
}
import gleamunison/llm_wire

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn cast(a: anything) -> Dynamic

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn uncast(a: Dynamic) -> anything

fn openai_cfg() -> ProviderConfig {
  ProviderConfig(
    provider: OpenAI,
    base_url: "https://api.openai.com/v1",
    api_key: "sk-test",
    model: "gpt-test",
    max_tokens: 1024,
    timeout_ms: 180_000,
    reasoning_effort: "",
  )
}

fn anthropic_cfg() -> ProviderConfig {
  ProviderConfig(
    provider: Anthropic,
    base_url: "https://api.anthropic.com",
    api_key: "sk-ant-test",
    model: "claude-test",
    max_tokens: 512,
    timeout_ms: 180_000,
    reasoning_effort: "",
  )
}

pub fn openai_request_shape_test() {
  let msgs = [Message(User, "Say hi")]
  let #(url, headers, body) = llm_wire.build_request(openai_cfg(), msgs)
  let assert True = url == "https://api.openai.com/v1/chat/completions"
  let assert True = list.contains(headers, #("authorization", "Bearer sk-test"))
  let assert True =
    list.contains(headers, #("content-type", "application/json"))
  let assert True = string.contains(body, "\"model\":\"gpt-test\"")
  let assert True = string.contains(body, "\"max_tokens\":1024")
  let assert True =
    string.contains(
      body,
      "\"messages\":[{\"role\":\"user\",\"content\":\"Say hi\"}]",
    )
}

pub fn reasoning_effort_included_when_set_test() {
  let cfg = ProviderConfig(..openai_cfg(), reasoning_effort: "max")
  let #(_, _, body) = llm_wire.build_request(cfg, [Message(User, "Hi")])
  let assert True = string.contains(body, "\"reasoning_effort\":\"max\"")
}

pub fn reasoning_effort_omitted_when_empty_test() {
  let #(_, _, body) =
    llm_wire.build_request(openai_cfg(), [Message(User, "Hi")])
  let assert False = string.contains(body, "reasoning_effort")
}

pub fn anthropic_request_extracts_system_test() {
  let msgs = [Message(System, "Be terse."), Message(User, "Hi")]
  let #(url, headers, body) = llm_wire.build_request(anthropic_cfg(), msgs)
  let assert True = url == "https://api.anthropic.com/v1/messages"
  let assert True = list.contains(headers, #("x-api-key", "sk-ant-test"))
  let assert True = list.contains(headers, #("anthropic-version", "2023-06-01"))
  // system goes to a top-level field, NOT into messages
  let assert True = string.contains(body, "\"system\":\"Be terse.\"")
  let assert True =
    string.contains(
      body,
      "\"messages\":[{\"role\":\"user\",\"content\":\"Hi\"}]",
    )
}

pub fn json_escaping_in_request_body_test() {
  let msgs = [Message(User, "quote \" backslash \\ newline\n")]
  let #(_, _, body) = llm_wire.build_request(openai_cfg(), msgs)
  let assert True = string.contains(body, "\\\" backslash \\\\ newline\\n")
}

pub fn parse_openai_response_test() {
  let body =
    "{\"id\":\"chatcmpl-1\",\"model\":\"gpt-test\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Hello!\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":3,\"completion_tokens\":2}}"
  let assert Ok(c) = llm_wire.parse_response(OpenAI, 200, body)
  let assert True = c == Completion("Hello!", "gpt-test", 3, 2)
}

pub fn parse_anthropic_response_test() {
  let body =
    "{\"id\":\"msg_1\",\"model\":\"claude-test\",\"content\":[{\"type\":\"text\",\"text\":\"Hi there\"}],\"usage\":{\"input_tokens\":5,\"output_tokens\":4}}"
  let assert Ok(c) = llm_wire.parse_response(Anthropic, 200, body)
  let assert True = c == Completion("Hi there", "claude-test", 5, 4)
}

pub fn parse_error_status_is_http_error_test() {
  let assert Error(err) =
    llm_wire.parse_response(OpenAI, 429, "{\"error\":\"rate limited\"}")
  let assert llm_types.HttpError(429, _) = err
}

pub fn mock_handler_returns_fixed_completion_test() {
  let expected = Completion("canned", "mock-model", 1, 1)
  let handler = llm.mock_handler(expected)
  let args = [
    cast(bit_array.from_string("[]")),
    cast(bit_array.from_string("{}")),
  ]
  let result = handler(args, fn(d) { d })
  let assert Ok(json_bin) = uncast(result)
  let assert Ok(text) = bit_array.to_string(json_bin)
  let assert True = string.contains(text, "\"content\":\"canned\"")
  let assert True = string.contains(text, "\"model\":\"mock-model\"")
}

pub fn ability_frame_targets_genesis_hash_test() {
  let handler = llm.mock_handler(Completion("x", "m", 0, 0))
  let frame = llm.frame(handler)
  let assert True = frame.ability == llm.ability_ref()
}
