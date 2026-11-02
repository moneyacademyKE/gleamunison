import envoy
import gleam/bit_array
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/option
import gleam/string
import gleamunison/cancellation
import gleamunison/dynamic_ffi.{from_dynamic, to_dynamic}
import gleamunison/effects.{type OpHandler, HandlerFrame}
import gleamunison/llm
import gleamunison/llm_budget.{
  type Budget, Budget, CircuitOpen, Closed, ConcurrencyExceeded,
  CostBudgetExceeded, ModelNotPinned, Open, TokenBudgetExceeded,
}
import gleamunison/llm_settlement
import gleamunison/llm_types.{type Completion, Completion, OpenAI}
import gleamunison/llm_wire
import gleamunison/transcript
import gleeunit/should
import llm_mock
import test_ffi.{budget_reset}

/// The handler's reply, read back as the typed result the
/// middleware contract promises.
fn as_result(d: Dynamic) -> Result(BitArray, BitArray) {
  from_dynamic(d)
}

fn test_budget() -> Budget {
  Budget(
    max_tokens: 1000,
    max_cost_micro_usd: 5000,
    max_concurrent: 2,
    window_ms: 60_000,
    allowed_models: ["gpt-4o-mini"],
    circuit_failure_threshold: 2,
    circuit_reset_ms: 30_000,
  )
}

fn call(handler: OpHandler) -> Result(BitArray, BitArray) {
  let args = [to_dynamic(bit_array.from_string("[]"))]
  as_result(handler(args, fn(d) { d }))
}

fn fake_completion() -> Completion {
  Completion(
    content: "ok",
    model: "gpt-4o-mini",
    input_tokens: 10,
    output_tokens: 5,
  )
}

// ---- pure policy -----------------------------------------------------------

pub fn admit_refuses_unpinned_model_test() {
  llm_budget.admit(test_budget(), llm_budget.new_usage(0), Closed, "gpt-4o", 0)
  |> should.equal(Error(ModelNotPinned("gpt-4o")))
}

pub fn admit_refuses_saturated_concurrency_test() {
  let usage = llm_budget.Usage(0, 0, 2, 0)
  llm_budget.admit(test_budget(), usage, Closed, "gpt-4o-mini", 0)
  |> should.equal(Error(ConcurrencyExceeded(2)))
}

pub fn admit_refuses_exhausted_token_budget_test() {
  let usage = llm_budget.Usage(1000, 0, 0, 0)
  llm_budget.admit(test_budget(), usage, Closed, "gpt-4o-mini", 0)
  |> should.equal(Error(TokenBudgetExceeded(1000)))
}

pub fn admit_refuses_exhausted_cost_budget_test() {
  let usage = llm_budget.Usage(0, 5000, 0, 0)
  llm_budget.admit(test_budget(), usage, Closed, "gpt-4o-mini", 0)
  |> should.equal(Error(CostBudgetExceeded(5000)))
}

pub fn admit_refuses_open_circuit_with_retry_after_test() {
  llm_budget.admit(
    test_budget(),
    llm_budget.new_usage(0),
    Open(0),
    "gpt-4o-mini",
    100,
  )
  |> should.equal(Error(CircuitOpen(29_900)))
}

pub fn admit_allows_half_open_probe_after_reset_test() {
  llm_budget.admit(
    test_budget(),
    llm_budget.new_usage(0),
    Open(0),
    "gpt-4o-mini",
    30_001,
  )
  |> should.equal(Ok(Nil))
}

pub fn window_roll_zeroes_counters_but_keeps_in_flight_test() {
  let usage = llm_budget.Usage(900, 4000, 1, 0)
  let rolled = llm_budget.effective_usage(usage, 60_000, 61_000)
  rolled.tokens |> should.equal(0)
  rolled.cost_micro_usd |> should.equal(0)
  rolled.in_flight |> should.equal(1)
  rolled.window_started_at |> should.equal(61_000)
}

pub fn circuit_opens_at_threshold_and_probe_failure_reopens_test() {
  llm_budget.after_failure(Closed, 1, 2, 100) |> should.equal(Closed)
  llm_budget.after_failure(Closed, 2, 2, 100) |> should.equal(Open(100))
  llm_budget.after_failure(llm_budget.HalfOpen, 1, 2, 200)
  |> should.equal(Open(200))
  llm_budget.record_success(Open(100)) |> should.equal(Closed)
}

pub fn cost_arithmetic_is_micro_usd_per_million_tokens_test() {
  llm_budget.cost_micro_usd(1_000_000, 0, 150, 600) |> should.equal(150)
  llm_budget.cost_micro_usd(500_000, 500_000, 150, 600) |> should.equal(375)
}

pub fn refusal_names_are_stable_machine_readable_vocabulary_test() {
  llm_budget.refusal_name(TokenBudgetExceeded(1000))
  |> should.equal("token_budget_exceeded:1000")
  llm_budget.refusal_name(CircuitOpen(250))
  |> should.equal("circuit_open_retry_after_ms:250")
  llm_budget.refusal_name(ModelNotPinned("m"))
  |> should.equal("model_not_pinned:m")
}

pub fn allowed_models_parses_comma_list_test() {
  llm_budget.parse_allowed_models(" a, b ,,c ") |> should.equal(["a", "b", "c"])
  llm_budget.parse_allowed_models("") |> should.equal([])
}

// ---- holder boundary ---------------------------------------------------------

pub fn allowed_models_empty_entries_match_the_pure_parser_test() {
  let key = "GLEAMUNISON_LLM_ALLOWED_MODELS"
  let previous = envoy.get(key)
  let assert Ok(Nil) = budget_reset()
  envoy.set(key, " a,,b ")
  let allowed = llm_budget.admit_call("allowlist-valid-test", "a")
  let _ = llm_settlement.release("allowlist-valid-test")
  let empty_model = llm_budget.admit_call("allowlist-empty-test", "")
  envoy.set(key, " , , ")
  let invalid_list =
    llm_budget.admit_call("allowlist-invalid-test", "any-model")
  let _ = budget_reset()
  restore_env(key, previous)
  llm_budget.parse_allowed_models(" a,,b ") |> should.equal(["a", "b"])
  llm_budget.parse_allowed_models(" , , ") |> should.equal([""])
  allowed |> should.equal(Ok(Nil))
  empty_model |> should.equal(Error("model_not_pinned:"))
  invalid_list |> should.equal(Error("model_not_pinned:any-model"))
}

pub fn spent_tokens_roll_over_after_the_first_window_test() {
  let window_key = "GLEAMUNISON_LLM_WINDOW_MS"
  let limit_key = "GLEAMUNISON_LLM_MAX_TOKENS"
  let models_key = "GLEAMUNISON_LLM_ALLOWED_MODELS"
  let old_window = envoy.get(window_key)
  let old_limit = envoy.get(limit_key)
  let old_models = envoy.get(models_key)
  let assert Ok(Nil) = budget_reset()
  envoy.set(window_key, "300")
  envoy.set(limit_key, "10")
  envoy.unset(models_key)
  let assert Ok(Nil) = llm_budget.admit_call("window-roll-test", "model")
  let assert Ok(Nil) = llm_settlement.release("window-roll-test")
  let assert Ok(Nil) = llm_settlement.success("window-roll-test", 10, 0)
  let before = llm_budget.admit_call("window-roll-test", "model")
  sleep(400)
  let after = llm_budget.admit_call("window-roll-test", "model")
  let _ = llm_settlement.release("window-roll-test")
  let _ = budget_reset()
  restore_env(window_key, old_window)
  restore_env(limit_key, old_limit)
  restore_env(models_key, old_models)
  before |> should.equal(Error("token_budget_exceeded:10"))
  after |> should.equal(Ok(Nil))
}

@external(erlang, "timer", "sleep")
fn sleep(milliseconds: Int) -> Nil

fn restore_env(key: String, previous: Result(String, Nil)) -> Nil {
  case previous {
    Ok(value) -> envoy.set(key, value)
    Error(Nil) -> envoy.unset(key)
  }
}

// ---- live settlement composition (complete_env) -----------------------------
// The dead budget_handler composition was deleted (bk-baac); these drive the
// one live admit → release → meter → report authority instead. Refusal and
// circuit paths are pre-transport, and 127.0.0.1:1 proves no network is
// needed — same technique as cancelled_token_refuses_before_transport_test.
// The old meters-on-success integration test is deliberately not migrated:
// driving complete_env's success path needs the fake-HTTP boundary harness
// (new infrastructure, out of scope for a deletion slice). Metering stays
// covered at both ends: cost arithmetic below, settlement boundary in
// llm_settlement_test.

pub fn complete_env_refuses_unpinned_model_without_calling_provider_test() {
  let assert Ok(Nil) = budget_reset()
  envoy.unset("ANTHROPIC_API_KEY")
  envoy.set("OPENAI_API_KEY", "sk-test")
  envoy.set("OPENAI_BASE_URL", "http://127.0.0.1:1")
  envoy.set("OPENAI_MODEL", "gpt-4o")
  envoy.set("GLEAMUNISON_LLM_ALLOWED_MODELS", "gpt-4o-mini")
  let assert Error(reason) = llm.complete_env("hi")
  string.contains(reason, "model_not_pinned") |> should.be_true
  envoy.unset("OPENAI_API_KEY")
  envoy.unset("OPENAI_BASE_URL")
  envoy.unset("OPENAI_MODEL")
  envoy.unset("GLEAMUNISON_LLM_ALLOWED_MODELS")
}

pub fn complete_env_opens_circuit_after_threshold_failures_test() {
  let assert Ok(Nil) = budget_reset()
  envoy.unset("ANTHROPIC_API_KEY")
  envoy.set("OPENAI_API_KEY", "sk-test")
  envoy.set("OPENAI_BASE_URL", "http://127.0.0.1:1")
  envoy.set("OPENAI_MODEL", "gpt-4o-mini")
  envoy.set("GLEAMUNISON_LLM_CIRCUIT_FAILURE_THRESHOLD", "2")
  // Two transport failures report through llm_settlement.failure...
  let assert Error(_) = llm.complete_env("hi")
  let assert Error(_) = llm.complete_env("hi")
  // ...so the third call is refused by the circuit, not the transport.
  let assert Error(refusal) = llm.complete_env("hi")
  string.contains(refusal, "circuit_open") |> should.be_true
  envoy.unset("OPENAI_API_KEY")
  envoy.unset("OPENAI_BASE_URL")
  envoy.unset("OPENAI_MODEL")
  envoy.unset("GLEAMUNISON_LLM_CIRCUIT_FAILURE_THRESHOLD")
}

pub fn complete_env_releases_concurrency_slot_after_each_call_test() {
  let assert Ok(Nil) = budget_reset()
  envoy.unset("ANTHROPIC_API_KEY")
  envoy.set("OPENAI_API_KEY", "sk-test")
  envoy.set("OPENAI_BASE_URL", "http://127.0.0.1:1")
  envoy.set("OPENAI_MODEL", "gpt-4o-mini")
  envoy.set("GLEAMUNISON_LLM_MAX_CONCURRENT", "1")
  // Two sequential calls both reach the transport and fail there: the slot
  // is released after each, not leaked. A leak would refuse the second call
  // with concurrency_exceeded before any transport.
  let assert Error(first) = llm.complete_env("hi")
  let assert Error(second) = llm.complete_env("hi")
  string.contains(first, "concurrency_exceeded") |> should.be_false
  string.contains(second, "concurrency_exceeded") |> should.be_false
  envoy.unset("OPENAI_API_KEY")
  envoy.unset("OPENAI_BASE_URL")
  envoy.unset("OPENAI_MODEL")
  envoy.unset("GLEAMUNISON_LLM_MAX_CONCURRENT")
}

// ---- redaction / retention ---------------------------------------------------

pub fn transcript_never_captures_llm_payloads_test() {
  // The redaction boundary is the transcript capture: LLM op args/results
  // are replaced by markers before anything can persist them.
  let secret = "sk-live-secret-prompt-content"
  let frames = [
    HandlerFrame(
      ability: llm.ability_ref(),
      ops: dict.from_list([
        #(0, llm_mock.mock_handler(fake_completion())),
      ]),
    ),
  ]
  let rec = transcript.start()
  let wrapped = transcript.wrap_frames(rec, frames)
  let assert [frame] = wrapped
  let assert Ok(handler) = dict.get(frame.ops, 0)
  let args = [to_dynamic(bit_array.from_string(secret))]
  let _ = handler(args, fn(d) { d })
  // Capture before stop: stopping erases the process-local log.
  let tape = transcript.capture(rec)
  transcript.stop(rec)
  let json = transcript.to_json(tape)
  string.contains(json, secret) |> should.be_false
  string.contains(json, "redacted") |> should.be_true
  // And a tape with redacted entries refuses replay: markers are not data.
  transcript.is_replayable(tape) |> should.be_false
}

pub fn provider_error_bodies_are_omitted_from_errors_test() {
  // A provider error body could echo request content; it is never surfaced.
  let assert Error(err) =
    llm_wire.parse_response(OpenAI, 500, "{\"echo\":\"sk-live-secret\"}")
  llm.error_string(err)
  |> string.contains("sk-live-secret")
  |> should.be_false
}

pub fn cancelled_token_refuses_before_transport_test() {
  // No network: a pre-cancelled token must refuse before a byte is sent.
  let cfg =
    llm_types.ProviderConfig(
      provider: OpenAI,
      base_url: "http://127.0.0.1:1",
      api_key: "test-key",
      model: "gpt-4o-mini",
      max_tokens: 16,
      timeout_ms: 1000,
      reasoning_effort: "",
    )
  let token = cancellation.new()
  cancellation.cancel(token)
  let handler = llm.provider_handler_with_cancellation(cfg, option.Some(token))
  let assert Error(reason) = call(handler)
  bit_array.to_string(reason)
  |> should_be_ok
  |> string.contains("cancelled")
  |> should.be_true
}

pub fn secret_rotation_needs_no_restart_test() {
  // Config resolution is per-call data flow: two sequential resolves see two
  // different keys with no process restart and no cached state.
  let env_a = fn(k) {
    case k {
      "OPENAI_API_KEY" -> Ok("sk-rotated-from")
      _ -> Error(Nil)
    }
  }
  let env_b = fn(k) {
    case k {
      "OPENAI_API_KEY" -> Ok("sk-rotated-to")
      _ -> Error(Nil)
    }
  }
  let assert Ok(cfg_a) = llm.resolve_config(OpenAI, env_a)
  let assert Ok(cfg_b) = llm.resolve_config(OpenAI, env_b)
  cfg_a.api_key |> should.equal("sk-rotated-from")
  cfg_b.api_key |> should.equal("sk-rotated-to")
}

// ---- helpers ------------------------------------------------------------------

fn should_be_ok(r: Result(String, Nil)) -> String {
  case r {
    Ok(s) -> s
    Error(_) -> ""
  }
}
