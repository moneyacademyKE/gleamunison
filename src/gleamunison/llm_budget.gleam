//// LLM budget and circuit policy — pure data in, decision out.
////
//// One owner for the vocabulary: budgets, usage, circuit state, and the
//// refusal names. The stateful holder (gleamunison_llm_budget.erl) applies
//// these functions; it never invents its own decisions. Rates and limits
//// arrive as data (env-derived at the edge), never hardcoded here.

import gleam/int
import gleam/list
import gleam/string

pub type Budget {
  Budget(
    /// Aggregate token ceiling per window (prompt + completion).
    max_tokens: Int,
    /// Aggregate cost ceiling per window, micro-USD (1/1_000_000 USD).
    max_cost_micro_usd: Int,
    /// In-flight call ceiling across the runtime.
    max_concurrent: Int,
    /// Rolling window length; counters reset when it elapses.
    window_ms: Int,
    /// Non-empty = only these models may run. Empty = unpinned (documented).
    allowed_models: List(String),
    /// Consecutive failures that open the circuit.
    circuit_failure_threshold: Int,
    /// How long an open circuit refuses before a half-open probe.
    circuit_reset_ms: Int,
  )
}

pub type Usage {
  Usage(
    tokens: Int,
    cost_micro_usd: Int,
    in_flight: Int,
    window_started_at: Int,
  )
}

pub type Circuit {
  Closed
  Open(opened_at: Int)
  HalfOpen
}

pub type Refusal {
  TokenBudgetExceeded(limit: Int)
  CostBudgetExceeded(limit_micro_usd: Int)
  ConcurrencyExceeded(limit: Int)
  CircuitOpen(retry_after_ms: Int)
  ModelNotPinned(model: String)
}

pub fn new_usage(now: Int) -> Usage {
  Usage(tokens: 0, cost_micro_usd: 0, in_flight: 0, window_started_at: now)
}

/// Rolling-window view: when the window has elapsed the counters read as
/// zeroed (the holder persists the roll on the next write).
pub fn effective_usage(usage: Usage, window_ms: Int, now: Int) -> Usage {
  case now - usage.window_started_at >= window_ms {
    True -> Usage(..new_usage(now), in_flight: usage.in_flight)
    False -> usage
  }
}

pub fn model_allowed(budget: Budget, model: String) -> Bool {
  case budget.allowed_models {
    [] -> True
    allowed -> list.contains(allowed, model)
  }
}

/// The admission decision. Checked in cheapest-to-most-expensive order:
/// pin, circuit, concurrency, then aggregate budgets.
pub fn admit(
  budget: Budget,
  usage: Usage,
  circuit: Circuit,
  model: String,
  now: Int,
) -> Result(Nil, Refusal) {
  case model_allowed(budget, model) {
    False -> Error(ModelNotPinned(model))
    True ->
      case circuit {
        Open(opened_at) -> {
          let retry_after = budget.circuit_reset_ms - { now - opened_at }
          case retry_after > 0 {
            True -> Error(CircuitOpen(retry_after))
            // Window has elapsed: a half-open probe may pass.
            False -> Ok(Nil)
          }
        }
        _ ->
          case usage.in_flight >= budget.max_concurrent {
            True -> Error(ConcurrencyExceeded(budget.max_concurrent))
            False ->
              case usage.tokens >= budget.max_tokens {
                True -> Error(TokenBudgetExceeded(budget.max_tokens))
                False ->
                  case usage.cost_micro_usd >= budget.max_cost_micro_usd {
                    True -> Error(CostBudgetExceeded(budget.max_cost_micro_usd))
                    False -> Ok(Nil)
                  }
              }
          }
      }
  }
}

pub fn begin(usage: Usage) -> Usage {
  Usage(..usage, in_flight: usage.in_flight + 1)
}

pub fn end(usage: Usage) -> Usage {
  Usage(..usage, in_flight: int.max(0, usage.in_flight - 1))
}

pub fn spend(usage: Usage, tokens: Int, cost_micro_usd: Int) -> Usage {
  Usage(
    ..usage,
    tokens: usage.tokens + tokens,
    cost_micro_usd: usage.cost_micro_usd + cost_micro_usd,
  )
}

/// Cost arithmetic stays here and only here: rates are micro-USD per
/// 1M tokens, supplied by the caller as data.
pub fn cost_micro_usd(
  prompt_tokens: Int,
  completion_tokens: Int,
  prompt_rate: Int,
  completion_rate: Int,
) -> Int {
  { prompt_tokens * prompt_rate + completion_tokens * completion_rate }
  / 1_000_000
}

pub fn record_success(_circuit: Circuit) -> Circuit {
  Closed
}

/// The holder owns the consecutive-failure counter; this decides what a
/// failure means given the circuit we were in. A failed half-open probe
/// re-opens immediately.
pub fn after_failure(
  circuit: Circuit,
  consecutive_failures: Int,
  threshold: Int,
  now: Int,
) -> Circuit {
  case circuit {
    HalfOpen -> Open(now)
    _ ->
      case consecutive_failures >= threshold {
        True -> Open(now)
        False -> Closed
      }
  }
}

pub fn refusal_name(refusal: Refusal) -> String {
  case refusal {
    TokenBudgetExceeded(limit) ->
      "token_budget_exceeded:" <> int.to_string(limit)
    CostBudgetExceeded(limit) ->
      "cost_budget_exceeded_micro_usd:" <> int.to_string(limit)
    ConcurrencyExceeded(limit) ->
      "concurrency_exceeded:" <> int.to_string(limit)
    CircuitOpen(retry) -> "circuit_open_retry_after_ms:" <> int.to_string(retry)
    ModelNotPinned(model) -> "model_not_pinned:" <> model
  }
}

pub fn refusal_retryable(refusal: Refusal) -> Bool {
  case refusal {
    CircuitOpen(_) -> True
    ConcurrencyExceeded(_) -> True
    _ -> False
  }
}

/// Parse the operator-facing allowlist: comma-separated, trimmed.
pub fn parse_allowed_models(text: String) -> List(String) {
  case string.trim(text) {
    "" -> []
    _ ->
      text
      |> string.split(",")
      |> list.map(string.trim)
      |> list.filter(fn(m) { m != "" })
  }
}
