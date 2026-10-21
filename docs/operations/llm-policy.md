# LLM Budget, Cancellation, and Privacy Policy

One policy owner: `gleamunison/llm_budget.gleam` holds every decision as a
pure function over data. One state owner: `gleamunison_llm_budget.erl` holds
the per-provider usage, circuit, and in-flight gauges. Composition happens
at the handler boundary (`llm_middleware.budget_handler`) and inside
`llm.complete_env` — every caller gets the same gate.

## Budgets (env, re-read per admission — rotation needs no restart)

| Env var | Default | Meaning |
|---|---|---|
| `GLEAMUNISON_LLM_MAX_TOKENS` | 1,000,000 | aggregate tokens per window |
| `GLEAMUNISON_LLM_MAX_COST_MICRO_USD` | 10,000,000 ($10) | aggregate cost per window |
| `GLEAMUNISON_LLM_MAX_CONCURRENT` | 4 | in-flight call ceiling |
| `GLEAMUNISON_LLM_WINDOW_MS` | 3,600,000 | rolling window length |
| `GLEAMUNISON_LLM_ALLOWED_MODELS` | (empty = unpinned) | comma-separated model pin |
| `GLEAMUNISON_LLM_CIRCUIT_FAILURE_THRESHOLD` | 3 | consecutive failures to open |
| `GLEAMUNISON_LLM_CIRCUIT_RESET_MS` | 30,000 | open → half-open probe delay |
| `GLEAMUNISON_LLM_PROMPT_RATE_MICRO_USD` | 0 | per 1M prompt tokens (estimate-only at 0) |
| `GLEAMUNISON_LLM_COMPLETION_RATE_MICRO_USD` | 0 | per 1M completion tokens |

Existing per-request bounds still apply: `LLM_MAX_TOKENS` (1..131,072),
`LLM_HTTP_TIMEOUT_MS` (1..180,000), retry ≤ 3 attempts with ≤ 1 s delay,
and only transient errors are retried (never settings/4xx/cancelled).

## Refusal vocabulary (machine-readable)

`token_budget_exceeded:<limit>` · `cost_budget_exceeded_micro_usd:<limit>` ·
`concurrency_exceeded:<limit>` · `circuit_open_retry_after_ms:<ms>` ·
`model_not_pinned:<model>` · `provider_cap_reached`

Circuit-open and concurrency refusals are retryable; the rest are terminal
until the window rolls or configuration changes.

## Cancellation

`provider_handler_with_cancellation` threads a caller-owned token into the
transport: pre-cancelled refuses before a byte is sent; in-flight
cancellation aborts the HTTP request. Cancellation errors are classified
terminal and are never retried.

## Metering

Actual `usage` tokens from the provider response are spent against the
window; cost arithmetic is micro-USD per 1M tokens with operator-supplied
rates. Concurrency slots are monitor-backed: a killed caller releases its
slot via the DOWN, a normal return via `release/1` — exactly once, never
leaked.

## Privacy

- **Transcripts**: the default capture policy redacts LLM op payloads at
  capture — ability, op index, and sequence survive; prompts and
  completions never reach the tape. A tape with redacted entries is
  honestly non-replayable (`is_replayable` is false). Deliberate fixture
  recording opts in via `transcript.start_with(CaptureAll)`; those
  artifacts contain what the recorded code sent — never point them at
  secrets.
- **Errors**: provider error bodies are omitted from surfaced errors
  (`provider_error_body_omitted`) — a provider echo can never leak a
  request.
- **Keys**: live in env only, travel only in request headers, are never
  logged, and are re-read per call so rotation is a `launchctl setenv` /
  shell re-export away — no restart.
- **Retention**: the recorder is process-local and dies with the process;
  tapes become durable only through an explicit `to_json` write of an
  already-redacted (default) artifact.

## Fake-provider regression coverage

`test/llm_budget_test.gleam` — 19 tests, zero network: admission refusals
(pin, concurrency, token, cost, circuit timing), window roll, circuit
open/probe/reclose, cost arithmetic, middleware admit/meter/refuse over a
mock handler, concurrency-slot release, transcript redaction +
non-replayability, error-body omission, pre-transport cancellation, and
rotation.
