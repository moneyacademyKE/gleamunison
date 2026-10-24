# Whole-codebase component audit — final re-audit — 2026-10-24

**Date:** 2026-10-24 EAT (UTC+3)
**Baseline:** `main` @ `f8908f8daada80a688e4df4e9eb870ce95eb7693`
**Fix branch:** `fix/component-audit-2026-10-24` @ `ef7f95a`
**Tracking:** audit `bk-c0ba`; owner-authorized fix set `bk-be00`.
**Scope:** component owners, callers, tests, scripts, CI, docs and bottlenecks. This is an evidence-backed re-audit, not a formal proof of every function.

## Verdict

The nine findings from the baseline audit now have targeted repairs and regressions. The final local gates are green: `gleam clean && gleam test`, format/check, the integrated production-boundary gate, artifact/release contracts, the default playbook, and the repaired post-fix probe all exit 0. The suite reports **649 tests**, the playbook reports **934 executable passes and 238 explicit exclusions**, and the artifact remains **3.24.0** with **13 engine modules and 0 test modules**.

That is not a production-readiness score. Hosted CI matrix legs, production load, paid-provider behavior, TLS, multi-node upgrades, and external OS isolation remain outside this local proof. The runtime is still correctly classified as an `authenticated-single-node-service`; it is not an OS sandbox for arbitrary untrusted code.

No push, release, publish, deploy, tag or merge occurred. The rebuilt escript and production-boundary witness remain workspace outputs and are excluded from the fix commits.

## Finding closure matrix

| ID | Baseline finding | Repair and live evidence | Status |
|---|---|---|---|
| F1 | Retraction dependency/alias reads collapsed storage failures into empty results. | `dependency_snapshot.read` owns one branch-local read and returns `StoreFailure`, `NamespaceFailure` or `CorruptDefinition`; `cli_unpublish` and `cli_purge` refuse before mutation. `test/retraction_safety_test.gleam` and the post-fix probe assert refusal. | **Closed — high confidence** |
| F2 | Mnesia delete acknowledged success without deleting the record. | `src/gleamunison_storage.erl:243-248` now performs `mnesia:delete/1` in a transaction and maps aborts to errors. `test/mnesia_delete_test.gleam` and the probe verify lookup returns `none` after deletion. | **Closed — high confidence** |
| F3 | LSP `Content-Length` used character/grapheme length instead of UTF-8 bytes. | `lsp_frame` encodes with `byte_size` and rejects negative lengths; the real stdio pump uses it. `test/lsp_framing_test.gleam`, `scripts/test_lsp_stdio.clj`, and the probe verify the five-byte `café` frame. | **Closed — high confidence** |
| F4 | MCP/index values crossed a Lisp source boundary through interpolation. | `lisp_literal` centralizes escaping; MCP/index paths carry hostile values as data, and Erlang result decoding uses term data rather than quote scraping. `test/datalog_literal_test.gleam` and the probe cover quotes, backslashes, newlines and Unicode. | **Closed — high confidence** |
| F5 | Ranking repeated corpus statistics and used quadratic score joins. | `rank` hoists BM25 weights; hybrid ranking uses keyed dictionaries for joins. `test/rank_parity_test.gleam` checks behavior. Synthetic warmed medians at 1,000 docs changed BM25 **78,472→336 µs** and hybrid **95,475→14,615 µs**; these are operation timings, not production p95. | **Closed — high confidence for the measured defect** |
| F6 | Dependency/evidence/namespace/index operations repeated broad scans or rebuilds. | Operation-local dependency, evidence and name snapshots, plus flat index datom accumulation, remove repeated work without adding invalidation state. Focused tests and the post-fix benchmark cover the paths. Evidence listings changed from **20→1**, reports **3→1**, namespace reads **3→1** in the focused probes. | **Closed — high confidence for the repaired paths; broader load remains unproven** |
| F7 | No common source/token/depth/form admission before parse/elaboration. | `source_budget` and the Erlang byte scanner enforce 1 MiB bytes, 100k tokens, depth 1024, 4096 forms and 16 KiB token/comment limits before recursive parsing. `test/source_budget_test.gleam` and the probe verify deep input is refused. | **Closed — high confidence for the stated limits** |
| F8 | CI diff checks had a green fallback and did not cover all changed/untracked production files. | CI uses strict `git diff --check HEAD --`; the boundary script scans tracked and untracked code, checks untracked whitespace and enforces the 500-LOC ceiling. `test_ci_contract.clj` and `test_verification_contract.clj` both exit 0; publish gates now include artifact, release and playbook contracts. | **Closed — high confidence for the local contracts; hosted matrix still pending** |
| F9 | README/witness/trust and count claims drifted. | README now says 649 tests, 934 passes + 238 exclusions, the current 2026-10-24 witness, and the single-signer trust boundary. The final witness records the integrated gate. Historical audit/planning docs retain old counts as dated history, not current claims. | **Closed — high confidence for current README/witness; historical docs remain archival** |

## Component re-audit

| Component | Live owners / evidence | Final verdict |
|---|---|---|
| CLI/store lifecycle | `cli_lifecycle`, `cli_unpublish`, `cli_purge`, storage adapters; full suite and CLI contracts | Explicit branch/store context; destructive paths now fail closed on unreadable safety inputs. |
| Lexer/parser/formatter | `source_budget`, lexer/parser, source-budget tests, parser gate | Shared pre-parse resource limits now exist. This is admission control, not an OS sandbox. |
| Elaboration/inference | elaboration/inference owners and full suite | No new type counterexample in this pass; not a soundness proof. |
| Compile/load/eval/effects | pipeline, `repl_eval`, `run_ref`, runtime tests and playbook | Evaluation budgets and descendant cleanup remain tested; parsing precedes runtime budgets. |
| Identity/codec/CAS | identity, codebase, codecs, CAS and artifact gates | Content identity and integrity checks remain explicit; no raw-chunk identity claim. |
| Storage | ETS/DETS/Mnesia adapters, deletion regression and integrated gate | Mnesia mutation contract is truthful; backend parity beyond covered APIs remains a future load target. |
| Namespace/history | namespace, dependency/name snapshots, branch tests | Branch reads are reused within operations; corrupt or unreadable safety state refuses. |
| Dependencies/retraction | dependency snapshot, store-deps tests, retraction regressions | Error/absence distinction is restored; persistent reverse indexing is intentionally deferred. |
| Search | rank, parity test, before/after synthetic probe | The measured repeated-statistics and join costs are repaired; synonym semantics and production p95 remain unclaimed. |
| Datalog/index | literal boundary, result decoder, flat datom accumulation, hostile-input tests | Values stay data at the boundary; generated index work no longer grows through repeated list appends. |
| HTTP/auth/static | HTTP owners, traversal/auth probes, integrated gate | Local caps/auth/traversal checks pass; this does not prove TLS or universal mailbox limits. |
| MCP | MCP/session/index owners, hostile literal tests | Supervised protocol and data-safe values; full external-client conformance remains untested. |
| LSP | lsp/lsp-frame/stdio owners, Unicode regression and real stdio probe | UTF-8 byte framing is now correct and bounded for the covered protocol path. |
| Sync | typed sync, TCP HMAC, acceptance tests and playbook | Authenticated bounded frames remain covered; large inventory cost is not eliminated. |
| Manifest/packages | manifest/pkg and effect/version tests | v2 effect flags and legacy parsing remain green. |
| Evidence/trust | evidence snapshot, trust/turnstile tests, trust operations doc | Single-signer production wiring is explicit; multi-key overlap remains library/test-only. |
| LLM/transcripts | controls, budgets, privacy tests | Local controls are covered; provider rates and paid-provider behavior are not verified here. |
| Observability/readiness | Erlang observability owners, recovery tests, operations docs | Bounded caches and recovery are covered; docs no longer substitute for a universal mailbox proof. |
| Build/artifact/dogfood | artifact, release, rollback and playbook contracts | Local release surface is reproducible and honest about exclusions. |
| CI/dependencies | test/publish workflows, CI contracts and manifest | Workflow gates are aligned locally; hosted OTP/OS matrix execution remains an explicit exclusion. |
| Docs | README, operations docs, witness and dated audits | Current headline claims point to current receipts; old counts remain only in dated historical records. |

## Bottleneck ranking after repair

The baseline search hot path was the largest measured CPU defect. The repaired synthetic medians show the expected order-of-magnitude reduction, but the benchmark is intentionally small and single-process.

| Rank | Remaining or repaired bottleneck | Evidence | Next sensible move |
|---:|---|---|---|
| 1 | Hybrid ranking still embeds each document and computes cosine values per call. | Post-fix probe: 14,615 µs at 1,000 synthetic docs versus 336 µs for BM25. | Measure repeated-query workloads before introducing a persistent vector cache. |
| 2 | Dependency scans still read a complete operation-local snapshot. | Post-fix probe: dependents 21,710 µs at 5,000 synthetic refs; evidence lookup 2,008 µs. | Add a reverse index only after real workload evidence justifies invalidation complexity. |
| 3 | Source admission still reads the source before the byte/token/depth checks. | `source_budget` bounds parser admission after the input is present; it does not replace an OS sandbox. | Put transport/file-size limits at every entry point and keep the external executor boundary explicit. |
| 4 | Full index and sync inventory operations remain broad by design. | Playbook/integration gates pass; no production p95 or concurrent measurement exists. | Profile real repositories before choosing an index/cache architecture. |

## Final verification receipts

All commands below ran sequentially on 2026-10-24 EAT from `/Users/moe/gleamunison` with the project PATH (`/opt/homebrew/bin:/Users/moe/.local/bin:$PATH`):

- `gleam clean && gleam test` — exit 0; **649 tests passed, 0 failures**. The suite emits expected negative-probe and supervisor output.
- `gleam format --check src test` — exit 0.
- `gleam check --target erlang` — exit 0; one pre-existing unused `None` import warning in `test/sync_accept_test.gleam`.
- `escript docs/audit/probes/2026-10-24-components.escript` — exit 0; storage-error refusal, Mnesia removal, UTF-8 framing, literal safety and parser budget all pass.
- `escript docs/audit/probes/2026-10-24-components.escript benchmark` — exit 0; final raw receipt: `docs/audit/probes/2026-10-24-benchmark-postfix.log`.
- `bb scripts/run_playbook_tests.clj` — exit 0; **934 passed, 238 excluded, 0 failed/skipped/timeouts**.
- `bb scripts/test_ci_contract.clj` — exit 0.
- `bb scripts/test_verification_contract.clj` — exit 0.
- `bb scripts/test_release_contract.clj` — exit 0; two clean artifacts byte-identical, SHA256 `65f95593adfb3ed11a65cff1367d7f81f2d614801df6c13b37efd9...`.
- `bb -e '(load-file "scripts/verify_production_boundaries.clj")'` — exit 0; integrated gate PASS, 15 gates PASS, witness `docs/verification/production-boundaries-2026-10-24.md`.
- `git diff --check` — exit 0.

## Explicit limits

This re-audit does not claim a hosted CI matrix pass, production HTTP/LSP/MCP load, TLS/mTLS, paid-provider accounting, multi-node upgrade safety, a CVE/license scan, or OS/container isolation. The strict playbook mode continues to report exit 1 by deliberate policy because its 238 prose/manual cases are excluded rather than falsely counted as executable passes.

## Simplicity certification

One policy owner now bounds source admission; one operation-local immutable view prevents repeated safety reads; one literal encoder preserves data at the language boundary; one transactional deletion path tells the truth. The fixes remove complecting repeated work without adding a persistent cache, framework, implicit peer fetch, or fake maturity score. That is the Rich Hickey-approved shape: fewer hidden states, more honest data, and proof attached to each claim.
