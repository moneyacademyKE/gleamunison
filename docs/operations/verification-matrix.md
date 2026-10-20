# Production-boundary verification matrix

**Date:** 2026-10-20 (EAT)
**Status:** Matrix frozen for the remaining production-gaps plan; rows become release evidence only when their command has a real receipt.
**Tracking:** Bankai `bk-c7bb`; GitHub issue [#25](https://github.com/moneyacademyKE/gleamunison/issues/25)

This matrix is the index from a boundary claim to a runnable refusal/success proof. A row marked **planned** is not evidence of a passing implementation. Every final witness must record the command, exit code, source/artifact revision, and any manual or environmental exclusion.

| Boundary | Profile(s) | Claim to prove | Runnable proof | Expected refusal/success | Status at 2026-10-20 |
|---|---|---|---|---|---|
| Loopback liveness | `local` | A live local process answers without implying readiness | `curl -i http://127.0.0.1:<port>/api/live` | HTTP 200 and `live=true` while the HTTP process answers | Existing v3.23.0 probe; re-run in integrated gate |
| Required-resource readiness | `local`, `authenticated-remote` | Readiness fails when required storage, version/schema, memory, provider, supervisor, or listener checks fail | `curl -i http://127.0.0.1:<port>/api/ready` plus `test/production_readiness_test.gleam` | HTTP 200 only for all required checks; HTTP 503 with bounded JSON otherwise | Existing; observational supervisors/queues/codebase/provider checks added in task 5 (`65f463f`) |
| Non-loopback bind gate | `authenticated-remote` | Remote binding cannot silently use local trust | `bb scripts/verify_production_boundaries.clj --transport` | Startup refuses without TLS/mTLS or an authenticated reverse-proxy contract; configured remote profile starts | Planned in task 3 |
| HTTP/MCP identity and scopes | `authenticated-remote` | Powerful routes reject missing/insufficient identity and admit authorized requests | `test/transport_auth_test.gleam` and live authorized/unauthorized probes | 401/403 for missing or insufficient scope; success for the declared scope | Planned in task 3 |
| Authenticated sync peer | `authenticated-remote` | Sync peers are typed, authenticated, replay-bound, and frame-bounded | `test/tls_sync_test.gleam` | Bad peer, bad identity, replay, oversized frame, or missing TLS refuses; authorized handshake succeeds | Planned in task 3 |
| Content admission | all | Immutable bytes bind to the requested content ref before admission | `test/trust_policy_test.gleam` and CAS recovery probe | Tamper, cross-subject, malformed, expired, revoked, or unsigned production input refuses | CAS integrity exists; signatures/policy planned in task 4 |
| Branch/pointer separation | all | Mutable branch pointers cannot masquerade as content identity | `test/trust_policy_test.gleam` | Cross-branch, replayed, or mismatched pointer refuses; valid pointer preserves requested branch | Namespace identity closed in v3.23.0; trust policy planned |
| Evidence provenance | all | Evidence names signer, subject, dependencies, expiry, and policy without becoming content identity | `test/trust_policy_test.gleam` | Missing signer, wrong subject, expired/revoked key, or replay refuses in production; valid rotated key succeeds | Planned in task 4 |
| Evaluation scope | `local`, `untrusted-execution` | Deadline/cancellation owns and drains permitted descendants | `test/execution_scope_test.gleam` | Child and grandchild are absent after timeout/cancel; normal success also cleans up | Prior timeout fix exists; new typed policy planned in task 2 |
| External sandbox requirement | `untrusted-execution` | Hostile code never runs in-process when the approved executor is absent | `test/sandbox_boundary_test.gleam` | Missing/unapproved executor, direct FFI/jet, or unenforceable limit refuses | Planned in task 2 |
| Resource saturation | all | Request/evaluation/MCP/SSE/sync queues and payloads are bounded | `test/resource_policy_test.gleam` plus saturation probe | Bounded rejection/backpressure; no unbounded mailbox, body, frame, or worker growth | Closed in task 5 (`bk-0b4e`, commit `65f463f`) |
| Crash/restart and drain | all | Supervisors recover predictably and drain without false readiness | `test/observability_recovery_test.gleam` | Kill/restart, drain, readiness failure, and recovery are visible and bounded | Closed in task 5 (`bk-0b4e`, commit `65f463f`) |
| Redacted observability | all | Metrics/logs/traces are machine-readable, bounded, and secret-free | `test/observability_recovery_test.gleam` plus export probe | Retention/cardinality caps hold; secrets/prompts are absent or redacted | Closed in task 5 (`bk-0b4e`, commit `65f463f`) |
| Artifact contract | all | Shipped artifact identifies its version/app closure and excludes test-only modules | `./build_escript.sh`; `bb scripts/test_release_contract.clj` | Build succeeds; declared version/app are present; disallowed BEAMs are absent | Closed in task 6 (`bk-a778`); reproducibility pinned and proven |
| Upgrade/rollback | all | Previous release, migration failure, drain, and rollback are isolated and reversible | `bb scripts/test_upgrade_rollback.clj` | Failed upgrade does not corrupt the fixture store; rollback restores the declared prior state | Closed in task 6 (`bk-a778`); v3.22.0 → v3.23.0 round-trip proven |
| LLM budget/cancellation | all | Provider calls have real time/token/cost/retry/concurrency limits and cancellation | `test/llm_budget_test.gleam` | Timeout/cancel stops transport; budget/circuit limits refuse further work; rotation succeeds without restart | Planned in task 7 |
| LLM privacy | all | Secret and sensitive prompt/response data do not enter durable diagnostics | `test/llm_budget_test.gleam` plus redaction scan | No configured secret appears in logs, traces, metrics, evidence, or transcripts | Planned in task 7 |
| Integrated boundary witness | all | Release classification matches evidence and exclusions | `bb scripts/verify_production_boundaries.clj` | Exit 0 only when required rows pass; manual/skipped rows are explicit; no publish/tag/merge/deploy | Planned in task 8 |

## Required final classifications

The final witness must emit exactly one of these classifications for the tested artifact/configuration:

- `safe-local-research-runtime`: loopback/local trust proven; no untrusted-code isolation claim.
- `authenticated-single-node-service`: remote transport, identity, scopes, and sync policy proven; untrusted execution remains disabled unless its separate proof passes.
- `untrusted-code-production-platform`: **forbidden** until external OS/container isolation, identity/trust, resource, recovery, compatibility, and privacy rows all pass.

## Evidence format

Each receipt should include:

- date/time in EAT;
- repository revision and artifact hash where applicable;
- exact command and environment/profile (without secrets);
- exit code and relevant bounded output;
- row IDs covered;
- manual checks, skips, or environmental blockers;
- explicit statement that the run performed no tag, Hex publish, merge, deployment, or public release.

**Rich Hickey check:** the matrix is a data table from boundary to proof, not a second orchestration framework. One claim, one owner, one runnable result; anything else stays an unresolved risk.
