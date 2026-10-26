# Bounded agent generation verification

**Date:** 2026-10-26 (EAT) · **Task:** `bk-6e13` · **Implementation commit:** `75083d8`

## Contract verified

`agent_generate` composes a checked content-addressed prompt, schema rendering,
SAP near-miss repair, a bounded provider/retry loop, inferred-type validation,
and the existing `agent_publish` admission path. Its result is a real selected-
branch content ref that verified execution and `/app` can run.

## Evidence

- `gleam test`: **734 passed, no failures** (implementation commit `75083d8`,
  log `build/verification/task8-final-tests.log`).
- A fenced, single-quoted, trailing-comma candidate publishes a typed term;
  `run_ref.run_verified_on_branch` and `app_route.request` return its value.
- A first invalid completion is followed by a corrected candidate; the second
  provider prompt contains the first rejection. Invalid output and exhausted
  attempts do not change selected-branch bindings.
- A candidate whose inferred type contradicts its requested signature is
  refused before evidence/admission. The red regression previously admitted
  `wrong-type: string` under a requested `int` signature.
- Untrusted `agent_generate` refuses before the storage adapter opens; the
  store file is not created. HTTP's earlier sandbox refusal remains 403.
- Real MCP HTTP → one-shot loopback [OI]-compatible provider → SAP → signed
  admission → `/app/generated-number` returns 200 and `42`. The content ref
  also executes through `run_ref`. This is not an external-provider test.
- Changing `base-value` reports `derived-value` through `patch.dependents`.
  The dependent keeps its content ref and its next verified run resolves the
  new selected-branch binding. No automatic dependent regeneration is claimed.
- `gleam format --check src test`: exit 0.
- `gleam check --target erlang`: exit 0; pre-existing unrelated warnings only.
- `git diff --check`: exit 0.

## Boundaries

- The public signature vocabulary is `int`, `float`, `string`, `bool`, and
  `(parameters) -> result`; internal `Plan` accepts an `ast.Type`.
- Each candidate has one target term plus its tests. Multi-term helper/app
  generation is not claimed.
- Generated tests satisfy the existing evidence policy; they are not a proof
  of functional correctness. Effectful definitions still require signed `io`
  evidence under the existing turnstile.
- Exhaustion may leave immutable prompt bytes for audit, but not branch writes.
- No external account, network provider, deployment, release, push, tag, or
  merge was used. The loopback provider and deterministic provider seam are
  explicit verification substitutes.

Design record: [ADR 0072](../adr/0072-bounded-agent-generation.md).
