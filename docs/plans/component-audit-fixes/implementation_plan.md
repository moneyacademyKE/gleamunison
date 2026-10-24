# Whole-codebase audit fixes

Tracking: `bk-be00`; audit: `bk-c0ba`. User authorization: “fix all”, 2026-10-24 EAT. Existing session checklist tasks 6–11 own execution. No new competing plan.

## Goal and constraints

Close F1–F9 from `docs/audit/2026-10-24-whole-codebase-component-audit.md` with regression evidence, measured before/after cost, and atomic local commits. Do not push, publish, deploy, merge or tag. Preserve the two pre-existing witness edits and rebuilt escript; never stage them. Python and parallel agents are prohibited.

No new dependencies. Keep production modules under 500 LOC; target 250. Preserve default `main`, explicit store/branch selection, legacy manifest parsing, and local-only execution with no implicit peer fetch. Same-VM budgets are not an OS sandbox.

## Rich Hickey gap analysis

| Current seam | Target | Rejected alternative / reason |
|---|---|---|
| Read failure collapses to empty | Result-returning safety decisions before mutation | A second result wrapper: standard Result is enough |
| Repeated store/namespace scans | Immutable operation-local graph/evidence snapshots | Persistent secondary index: adds recovery/invalidation before measurements justify it |
| Grapheme framing | UTF-8 byte framing with bounded length | More buffering abstractions without correcting units |
| String arguments become Lisp | One literal encoder, data stays data | A hidden escaping grammar per caller |
| Quadratic BM25 + joins | Once-per-query statistics, keyed score joins | Vector cache layered over quadratic scoring |
| Unbounded source entry | One composable admission owner | Independent per-command policies that drift |
| Green fallback and stale docs | Truthful CI exits and receipt-derived claims | A prettier maturity score without a rubric |

Utility wins only if correctness is preserved. Priority: data safety, protocol correctness, measured speed, then docs. No arbitrary performance promises.

## 1. Retraction and storage safety (task 6)

[MODIFY] `store_deps.gleam`, `cli_unpublish.gleam`, `cli_purge.gleam`: checked reads and fail-closed mutation admission. Distinguish a genuinely absent branch from corrupt/unreadable branch state. Keep read-only compatibility wrappers but do not use them for destructive decisions.

[MODIFY] `namespace.gleam`: validate the prior head before writing a new head; no corruption-to-new-branch fallback. [NEW] focused snapshot module if shared safe reads would make an existing owner too large.

[MODIFY] `gleamunison_storage.erl`: real Mnesia deletion transaction with error propagation. [NEW/MODIFY] backend parity and failure-injection tests, including no mutation on refused retraction. Each independent fix gets its own commit and full green suite.

Risk: metadata chunks and mutable branch pointers share the store with definitions. Validate/classify them correctly rather than interpreting every non-definition as corruption or skipping actual corrupt definitions.

## 2. Protocol and literal boundaries (task 7)

[MODIFY] `lsp.gleam`, `cli_lsp.gleam`, stdio FFI: byte count/slicing, bounded nonnegative lengths, real Unicode and concatenated-frame tests. [MODIFY] `mcp_session.gleam`, `codebase_index.gleam`: one Lisp string encoder, round-trip hostile quotes/backslashes/newlines without source execution. Do not confuse JSON escaping with language-literal escaping.

## 3. Measured cost removal (task 8)

[MODIFY] `rank.gleam`: hoist corpus document frequencies, key score joins, retain scores and tie ordering. [MODIFY] session/index code only where it eliminates measured repeat work.

[MODIFY/NEW] operation-local dependency/evidence/namespace snapshots; one read owner and no persistent cache authority. Fix accumulating-list append/membership costs in graph construction. Preserve self-hosted Datalog. Compare identical warmed synthetic workloads against the recorded baseline; do not call synthetic medians production p95.

## 4. Source admission (task 9)

[NEW] small source-budget owner with bytes/tokens/nesting/forms. [MODIFY] actual parser, verifier, formatter, MCP/LSP/CLI entries so admission precedes expensive conversion/compilation. Tests cover huge/deep input, strings/comments, valid controls, and normal playbook programs. Internal generated Datalog source must not accidentally become an unbounded bypass or be broken by arbitrary limits.

## 5. CI and documentation (task 10)

[MODIFY] workflows and gate selection: no `failing-check || empty-diff` false-green, include dirty/new files in LOC checks, keep publish prerequisites aligned without invoking publication locally.

[MODIFY] README/CHANGELOG/operations/script docs: remove contradictory counts, library-only trust claims and hard-mailbox-bound overclaims. Describe exactly the tested contract. Change aliases only if actually needed; manual/prose exclusions stay explicit.

## 6. Completion and re-audit (task 11)

Update audit probe assertions to repaired behavior (keep the baseline log). Rerun clean suite, format, check, integrated gate and default playbook sequentially. Re-audit every finding from live code, mark only proved repairs closed, upload current Markdown after each edit, and produce a final walkthrough with SHAs, commands/exit codes and benchmark limits.

## Verification commands

Prefix all Gleam/BB commands with `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH`.

- `gleam test`: red behavior regression first; green full suite per atomic change.
- `gleam format --check src test` and `gleam check --target erlang`: exit 0.
- `bb scripts/run_playbook_tests.clj`: exit 0, zero failures/timeouts, honest exclusions.
- `bb scripts/verify_production_boundaries.clj`: exit 0 with every required gate green.
- `escript docs/audit/probes/2026-10-24-components.escript`: repaired assertions plus comparable timings, exit 0.
- `git diff --check`, `wc -l` changed modules, exact staged-path review: exit 0, no production module at/above 500 LOC.

External issue publication is not authorized by the local fix request. Bankai holds the tracked defects; this document records reproduction and implementation scope for a manual issue/PR if needed later.
