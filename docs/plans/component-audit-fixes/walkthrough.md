# Component-audit fix walkthrough — 2026-10-24

**Branch:** `fix/component-audit-2026-10-24`
**Scope:** owner-authorized repairs for the component audit; local verification only.
**Status:** all nine baseline findings have targeted closure evidence. No push, publish, release, deploy, merge or tag occurred.

## What changed

- Retraction safety now distinguishes storage, namespace and corrupt-definition failures from absence; destructive CLI paths refuse before mutation.
- Mnesia deletion now executes transactionally and the regression verifies the payload is gone.
- LSP framing uses UTF-8 byte lengths and rejects negative lengths; the real stdio path has a Unicode regression.
- MCP and index values cross one escaped literal/data boundary; Erlang result decoding preserves term data.
- BM25 corpus statistics and hybrid score joins are hoisted/keyed; focused parity tests protect behavior.
- Dependency, evidence and namespace operations reuse operation-local immutable snapshots; index datoms accumulate without repeated list appends.
- Source admission now enforces byte, token, depth, form and token/comment-byte limits before recursive parsing.
- CI and publish contracts use strict diff/LOC checks and include artifact, release, playbook and real LSP stdio gates.
- README and the current witness link now point at the 2026-10-24 receipts and retain the honest single-node/external-sandbox boundary.

## Verification receipts

All commands ran sequentially on 2026-10-24 EAT from `/Users/moe/gleamunison` with `/opt/homebrew/bin:/Users/moe/.local/bin` first in `PATH`.

| Command | Result |
|---|---|
| `gleam clean && gleam test` | exit 0; 649 passed, 0 failures |
| `gleam format --check src test` | exit 0 |
| `gleam check --target erlang` | exit 0; one pre-existing unused `None` warning |
| `escript docs/audit/probes/2026-10-24-components.escript` | exit 0; all post-fix contracts pass |
| `escript docs/audit/probes/2026-10-24-components.escript benchmark` | exit 0; final log saved under `docs/audit/probes/2026-10-24-benchmark-postfix.log` |
| `bb scripts/run_playbook_tests.clj` | exit 0; 934 passed, 238 explicit exclusions, 0 failed/skipped/timeouts |
| `bb scripts/test_ci_contract.clj` | exit 0 |
| `bb scripts/test_verification_contract.clj` | exit 0 |
| `bb scripts/test_release_contract.clj` | exit 0; two clean builds byte-identical |
| `bb -e '(load-file "scripts/verify_production_boundaries.clj")'` | exit 0; integrated gate PASS, 15 gates PASS |
| `git diff --check` | exit 0 |

## Benchmark comparison

The warmed synthetic probe is not an HTTP p95 or production SLA. At 1,000 documents, BM25 changed from **78,472 µs** to **336 µs** and hybrid ranking from **95,475 µs** to **14,615 µs**. Hybrid remains the dominant measured search cost because it embeds each document per call; repeated-query measurements should precede a persistent vector cache.

## Remaining limits

Hosted OTP/OS CI matrix execution, production concurrent load, TLS/mTLS, paid-provider accounting, multi-node upgrade drills, CVE/license scanning and OS/container isolation were not claimed. The strict playbook mode remains intentionally non-green when manual/prose exclusions are treated as skipped; the default mode is the receipt-bearing 934-pass run.

## Simplicity certification

The repair set prefers one owner per policy and operation-local immutable data over a persistent cache or framework. It removes repeated work, preserves explicit errors, and keeps external isolation as an explicit boundary instead of pretending the BEAM is a sandbox.
