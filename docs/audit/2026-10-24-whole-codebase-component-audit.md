# Whole-codebase component audit — 2026-10-24

**Date:** 2026-10-24 EAT (UTC+3)
**Baseline:** `main` @ `f8908f8daada80a688e4df4e9eb870ce95eb7693`
**Tracking:** audit `bk-c0ba`; owner-authorized fixes `bk-be00`.
**Scope:** component owners, callers, tests, scripts, CI, docs and bottlenecks. Review depth varies; this is not a formal proof of every function.

## Verdict

**The tests pass; the system is not fully mature.** Three correctness defects reproduced after the green gate: retraction checks turn storage errors into empty results, Mnesia deletion is a success-returning no-op, and LSP framing miscounts Unicode bytes. MCP graph tools also confuse string arguments with generated Lisp syntax. Search has a measured quadratic cost; storage scans are linear but repeated during closure work.

**Verification score: 15/15 local gate checks passed.** That is not an operational-readiness score. The first draft's 78/100 maturity number is withdrawn: it had no defined rubric. Open correctness defects outweigh a reassuring number.

The audit changed no production source. Verification regenerated the already-dirty escript and current witness. Neither those outputs nor the pre-existing older witness belongs in an audit/fix commit. No push, release, publish, deploy, tag or merge occurred. The user subsequently authorized fixing all findings; fixes must be verified before findings close.

## Confirmed findings

Gleam paths below are relative to `src/gleamunison/` unless prefixed with `src/`.

| ID | Severity / confidence | Finding and evidence | Fix owner |
|---|---|---|---|
| F1 | High / high | Failed dependency/alias reads become empty lists; destructive callers accept empty: `store_deps.gleam:39-65,74-83,102-108`; `cli_unpublish.gleam:78-93,102-125`; `cli_purge.gleam:73-96` | `bk-9f57` |
| F2 | Medium / high | Mnesia delete returns success without removing bytes: `src/gleamunison_storage.erl:243`; adapter wiring `storage.gleam:279` | `bk-1201` |
| F3 | Medium / high | LSP Content-Length uses graphemes rather than UTF-8 bytes: `lsp.gleam:32-42,65-66`; response pump `cli_lsp.gleam:31-32` | `bk-1180` |
| F4 | Medium / high | MCP names/kinds and index values are interpolated into Lisp source: `mcp_session.gleam:167-212`; `codebase_index.gleam:113-132` | `bk-a8c4` |
| F5 | Medium / high | Ranking repeats corpus scans inside per-document scoring and uses quadratic joins: `rank.gleam:74-95,138-142,247-295` | `bk-95f2` |
| F6 | Medium / high for source shape | Repeated store scans, namespace reloads and graph-program rebuilds: `store_deps.gleam:194-216`; `evidence.gleam:251-271`; `run_ref.gleam:319-342`; `mcp_session.gleam:207-218` | `bk-be00` |
| F7 | Medium / medium for impact | No common source/token/depth budget before parsing/elaboration: `lexer.gleam:29-94`; `parser.gleam:22-57`; `repl_eval.gleam:149-199` | `bk-be00` |
| F8 | Medium / high | CI checks differ; whitespace failure has a green fallback: `.github/workflows/test.yml:99-100`; `publish.yml:18-25`; LOC selection `scripts/verify_production_boundaries.clj:68-80` | `bk-be00` |
| F9 | Low–medium / high | Contradictory counts, witness links and trust/runtime docs: `README.md:11-14,185-188,229-241,261,448`; `CHANGELOG.md:17-20`; `docs/operations/observability.md:21-26` | `bk-be00` |

### F1 — failed reads are not evidence of no users

A failing adapter produces `dependents_after_storage_error=[]` and `aliases_after_storage_error=[]` in the durable probe. `unpublish` accepts `[]` at both checks before rewriting index, namespace and content; `purge` uses the same list-based decision. No production data was deleted by the probe. Error erasure is observed; unsafe admission follows from the caller branches.

Related mutation paths also substitute an empty namespace/index on read errors (`cli_unpublish.gleam:145-159`, `cli_purge.gleam:183-185,210-213`). Distinguish absence from read/corruption failure, propagate errors, and prove refusals leave every representation unchanged. Safety before optimization.

### F2 — Mnesia acknowledgement lies

An isolated RAM table is populated, delete returns `{ok,nil}`, then lookup still returns the payload. The public adapter advertises deletion; its Erlang implementation unconditionally succeeds. The normal Mnesia test covers insert/lookup/list/close, not deletion (`test/roadmap_tdd_test.gleam:190-207`). This affects Mnesia callers; CLI retraction uses DETS, not this backend.

### F3 — Unicode breaks framing

A five-byte UTF-8 body containing `café` is emitted with `Content-Length: 4`. The pure decoder rejects a correctly five-byte-framed counterpart; an ASCII control succeeds. The encoder is used by the actual stdio response pump, so non-ASCII replies can desynchronize clients. Also validate bounded nonnegative lengths and test the real stdio Unicode round trip; binary-mode comments do not prove bytes and characters agree.

### F4 — strings cross into program syntax

On an empty session, a normal missing name returns `Ok([])`, but a quote-only name or kind produces `tokenize: Unclosed (`. Query arguments and index values bypass a language-literal encoder. This proves literal/source confusion, **not demonstrated remote code execution**. Use a single correct Lisp literal boundary or structured queries; test quotes, backslashes and newlines.

## Measured bottlenecks

Reproduce with `escript docs/audit/probes/2026-10-24-components.escript` after build. Raw output: `docs/audit/probes/2026-10-24-components.log`. Baseline probe exit 0 means defects reproduced, **not fixed**; fix verification must change those assertions.

OTP 29, macOS arm64, one warm-up and three timed samples per size; medians below. Search documents each have four identical words and distinct IDs, with a two-term query. Store fixtures are tiny independent integer definitions in ETS; setup excluded. These are synthetic operation timings, **not HTTP p95, concurrent load, DETS performance or SLAs**.

| Operation | Small | Medium | Larger |
|---|---|---|---|
| BM25 | 100 docs: 0.872 ms | 500: 20.008 ms | 1,000: 80.285 ms |
| Hybrid rank | 100 docs: 2.390 ms | 500: 27.816 ms | 1,000: 97.321 ms |
| Dependency scan | 100 refs: 0.482 ms | 1,000: 4.298 ms | 5,000: 20.583 ms |
| Evidence lookup | 100 refs: 0.038 ms | 1,000: 0.374 ms | 5,000: 1.744 ms |

**1. Search is the clearest measured CPU bottleneck.** `rank` calls `idf(term, all)` within the document/term loop; each IDF rescans every document/token list. Cost is roughly O(Q × D² × L), not just linear tokenization. Hybrid scoring uses `list.find` per document to join scores, adding O(D²). It also rebuilds AST body tokens and vectors. First hoist corpus statistics and key score joins; a persistent vector cache would otherwise hide the quadratic defect under more state.

**2. Store scans multiply.** Exclusive closure repeats a whole-store dependency query per candidate/round. Evidence reads enumerate and hash all candidates, parsing only hash-matching chunks. Single ETS scans were modest in this baseline. Prefer an operation-local dependency/evidence snapshot before adding a persistent reverse index and its recovery/invalidation obligations.

**3. Graph queries rebuild programs.** `datoms_of` repeatedly appends growing lists and scans the full name list for membership. MCP graph requests regenerate index source and prepend/evaluate the engine. Use set membership and an immutable session snapshot without introducing another database.

**4. Run-by-hash reloads namespaces.** `resolve_name_ref` invokes `namespace.load_current` inside the recursive resolver; its once-per-run comment is not supported by that path. Carry one selected-branch snapshot. Loaded-ref tracking already avoids some duplicate traversal, so this is not a claim that every node is recompiled.

**5. Source admission is a resource risk, not a reproduced crash.** Depths 100, 1,000 and 5,000 parsed successfully; the last source was 40,001 bytes. HTTP has a 1 MiB body cap, but parser APIs and local-file entry points have no shared syntax budget. Evaluation-process limits begin after parsing/elaboration/compilation. Depth acceptance alone is not proof of VM failure.

## Component assessment

| Component | Reviewed owners / proof | Verdict / work remaining |
|---|---|---|
| CLI/store lifecycle | Entry module, `cli_lifecycle`, `cli_store`, CLI truth/errors | Explicit branch/store context; F1 retraction errors remain. Level table loading is lazy. |
| Lexer/parser/formatter | Grammar owners, parser battery, format gate | Normal cases pass; common admission needed (F7). |
| Elaboration/inference | `elaborate`, `elab_term`, `inference`, suite | No new type counterexample found; not a soundness proof. Costs precede eval budgets. |
| Compile/load/eval/effects | `pipeline`, `repl_eval`, `run_ref`, scope/effects tests | Runtime budgets/descendant cleanup tested; namespace work F6. BEAM containment is not OS isolation. |
| Identity/codec/CAS | `identity`, `codebase`, codec, oversize probe | Admission and invalid-size refusals pass; content identity is not raw chunk identity. |
| Storage | Gleam adapter/Erlang implementation, backend tests | ETS/DETS/partitioned-DETS baseline passes; Mnesia mutation contract broken (F2). |
| Namespace/history | `namespace`, branch/run-by-hash tests | Branch/identity checks exist; failure-to-empty and repeated loads F1/F6. |
| Dependencies/retraction | `store_deps`, unpublish/purge | Unsafe error erasure and repeated scans F1/F6. |
| Search | `rank`, session search, warm benchmark | Quadratic cost F5. Trigrams provide lexical/morphological, not synonym semantics. |
| Datalog | Engine, `cli_datalog`, `codebase_index` | 13 engine modules packaged; unsafe literals/rebuilds F4/F6. |
| HTTP/auth/static | HTTP/routes/util/static owners, boundary gate | Body/header/worker caps and auth/traversal checks pass. Acceptor sends messages before worker-cap check: no proof of a hard mailbox cap. |
| MCP | `mcp`, `mcp_server.gleam`, Erlang session, tests | Supervised protocol; immutable session data. F4–F6 remain. |
| LSP | `lsp`, `cli_lsp`, `lsp_features`, tests | Diagnostics/hover/completion exist; byte framing broken (F3). |
| Sync | Typed sync, TCP HMAC, acceptance tests | Authenticated bounded frames, unsolicited-chunk refusal; whole inventory still expensive. Selective fetch exists. |
| Manifest/packages | `manifest`, `pkg`, effect/version tests | v2 effect flags/legacy parsing exist. Prior missing-effect finding is fixed, not repeated. |
| Evidence/trust | `evidence`, `trust`, turnstile tests | Single-signer production policy wired; overlap library-only. Evidence scan F6; README trust row stale. |
| LLM/transcripts | LLM/controls/budgets/privacy tests | Locally tested controls; no paid provider probe. Operator rates required for nonzero cost accounting. |
| Observability/readiness | Erlang owners, recovery tests, docs | Bounded caches and drain/recovery proof; universal mailbox/list bounds overclaimed in docs. |
| Build/artifact/dogfood | Artifact/release/rollback/playbook gates | Local contract passes; 238 prose/manual exclusions never count as passing tests. |
| CI/dependencies | Workflows, Gleam lock manifest, `bb.edn` | Six core matrix combinations configured, not freshly remotely verified. Publish/whitespace/LOC gaps F8. |
| Docs | README/CHANGELOG/scripts/operations/prior audits | 508/611 vs 617 tests; 85/100 vs 97/104 test/source files; old witness and trust-unwired wording F9. |

## Receipts and limits

- `gleam test`: exit 0, **617 passed, no failures**; format/check exit 0. Existing unused `None` import warning.
- Integrated boundary gate: exit 0, **15/15 PASS**, witness `docs/verification/production-boundaries-2026-10-24.md`.
- Default playbook: exit 0, **934 passed, 238 excluded**, no failures/skips/timeouts. Strict: exit 1, same 238 reported skipped by policy.
- Artifact: exit 0, version **3.24.0**, **13** engine modules, **0** disallowed test modules. Reproducibility/upgrade batteries pass. Upgrade script uses v3.22.0 despite older prose saying v3.23.0.
- Audit probe exit 0; F1/F2/F3 and benchmarks reproduced. Separate MCP quote probe exit 0 with controlled errors.
- Inventory: **104** Gleam sources, **43** production Erlang + **53** genesis + **4** test helpers; **97** Gleam tests, **13** Lisp engine modules, **40** playbook docs.
- No full CVE/license scan, production load/provider/TLS test, multi-node upgrade drill, complete LSP/MCP conformance suite or OS-sandbox claim.

## Repair order and simplicity check

1. F1/F2: truthful failures and deletion, with no-mutation-on-refusal/backend parity tests.
2. F3/F4: bounded byte framing and one literal boundary, with real Unicode/hostile-string regressions.
3. F5/F6: hoist corpus work, key joins, use operation-local snapshots; compare identical benchmarks.
4. F7: common admission before parse/compile, preserving valid playbook input.
5. F8/F9: truthful CI gates; synchronize docs from fresh tests, retaining manual exclusions.

**Rich Hickey:** distinguish error from absence, bytes from characters, data from syntax. Remove repeated work before inventing caches. One policy owner; no framework, implicit peer fetch or secret grammar.
