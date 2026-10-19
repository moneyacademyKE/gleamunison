import gleam/bit_array
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/string
import gleamunison/cli_llm
import gleamunison/llm
import gleamunison/llm_middleware
import gleeunit/should

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn cast(value: a) -> Dynamic

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn uncast(value: Dynamic) -> a

@external(erlang, "gleamunison_ffi_test", "pd_counter_inc")
fn increment(key: BitArray) -> Int

@external(erlang, "gleamunison_ffi_test", "pd_counter_get")
fn count(key: BitArray) -> Int

fn env_with(settings: List(#(String, String))) -> cli_llm.EnvLookup {
  let values =
    dict.from_list([#("OPENAI_API_KEY", "synthetic-control-key"), ..settings])
  fn(key) { dict.get(values, key) }
}

pub fn invalid_timeout_settings_are_rejected_test() {
  list.each(["0", "-1", "180001", "not-an-int"], fn(value) {
    cli_llm.resolve_config(
      llm.OpenAI,
      env_with([#("LLM_HTTP_TIMEOUT_MS", value)]),
    )
    |> should.be_error
  })
}

pub fn invalid_token_settings_are_not_silently_defaulted_test() {
  list.each(["0", "-1", "131073", "not-an-int", ""], fn(value) {
    cli_llm.resolve_config(llm.OpenAI, env_with([#("LLM_MAX_TOKENS", value)]))
    |> should.be_error
  })
}

pub fn unknown_reasoning_effort_is_rejected_test() {
  cli_llm.resolve_config(
    llm.OpenAI,
    env_with([#("LLM_REASONING_EFFORT", "turbo")]),
  )
  |> should.be_error
}

pub fn known_reasoning_efforts_are_accepted_test() {
  list.each(["", "low", "medium", "high", "max"], fn(value) {
    cli_llm.resolve_config(
      llm.OpenAI,
      env_with([#("LLM_REASONING_EFFORT", value)]),
    )
    |> should.be_ok
  })
}

pub fn remote_plaintext_provider_url_is_rejected_test() {
  cli_llm.resolve_config(
    llm.OpenAI,
    env_with([
      #("OPENAI_BASE_URL", "http://remote.invalid/v1"),
    ]),
  )
  |> should.be_error
}

pub fn loopback_plaintext_model_server_remains_supported_test() {
  cli_llm.resolve_config(
    llm.OpenAI,
    env_with([
      #("OPENAI_BASE_URL", "http://127.0.0.1:11434/v1"),
    ]),
  )
  |> should.be_ok
}

pub fn credential_header_injection_is_rejected_test() {
  cli_llm.resolve_config(
    llm.OpenAI,
    env_with([
      #("OPENAI_API_KEY", "synthetic\r\nInjected: yes"),
    ]),
  )
  |> should.be_error
}

pub fn empty_credentials_and_model_are_rejected_test() {
  cli_llm.resolve_config(llm.OpenAI, env_with([#("OPENAI_API_KEY", "")]))
  |> should.be_error
  cli_llm.resolve_config(llm.OpenAI, env_with([#("OPENAI_MODEL", "")]))
  |> should.be_error
}

pub fn unsupported_anthropic_effort_is_not_silently_ignored_test() {
  let settings =
    dict.from_list([
      #("ANTHROPIC_API_KEY", "synthetic-ant-key"),
      #("LLM_REASONING_EFFORT", "max"),
    ])
  cli_llm.resolve_config(llm.Anthropic, fn(key) { dict.get(settings, key) })
  |> should.be_error
}

pub fn retry_attempts_have_a_hard_cap_test() {
  let key = <<"retry-hard-cap">>
  let inner = fn(_, cont) {
    let _ = increment(key)
    cont(cast(Error(<<"transient failure">>)))
  }
  let handler =
    llm_middleware.retry_handler(inner, llm_middleware.RetryPolicy(50, 0))
  let response: Result(BitArray, BitArray) =
    uncast(handler([], fn(value) { value }))
  response |> should.be_error
  count(key) |> should.equal(3)
}

pub fn terminal_errors_are_not_retried_test() {
  list.each(
    ["cancelled", "settings: invalid", "http 401", "decode: bad shape"],
    fn(message) {
      let key = bit_array.from_string("terminal:" <> message)
      let inner = fn(_, cont) {
        let _ = increment(key)
        cont(cast(Error(bit_array.from_string(message))))
      }
      let handler =
        llm_middleware.retry_handler(inner, llm_middleware.RetryPolicy(3, 0))
      let response: Result(BitArray, BitArray) =
        uncast(handler([], fn(value) { value }))
      response |> should.be_error
      count(key) |> should.equal(1)
    },
  )
}

pub fn provider_http_error_body_is_not_exported_test() {
  let assert Error(error) =
    llm.parse_response(
      llm.OpenAI,
      401,
      "synthetic-control-key authorization payload",
    )
  llm.error_string(error)
  |> string.contains("synthetic-control-key")
  |> should.be_false
}
