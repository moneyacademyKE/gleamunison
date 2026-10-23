# Run-by-hash maturity fixes

**Date:** 2026-10-24 EAT (UTC+3)
**Tracking:** Bankai `bk-ac11` (cycle 1)
**Source audit:** `docs/audit/2026-10-23-run-by-hash.md`
**Status:** implementation plan; no production code is changed by this document.

## Goal

Make the run-by-hash contract truthful and composable without expanding the product into a new sandbox or trust-distribution system. The first obligation is to make an absent content hash classify identically in text and JSON modes. The remaining work is only what the current audit confirms as a high/medium blocker; design risks and historical documentation are handled separately.

## Selected fixes

### 1. Settle content existence before evidence admission — High

**Problem:** `src/gleamunison/run_ref.gleam` settles existence before evidence in `run_verified`, but `run_verified_raw` (the JSON path) calls `evidence_gate` first. `run --json <absent-ref>` therefore returns exit 1 for missing production signing configuration instead of exit 2 for missing content.

**Files:**

- Modify `src/gleamunison/run_ref.gleam`.
- Modify the focused run/CLI test file(s) that cover `run_verified_raw`, exit classification, and JSON output.
- Modify `docs/walkthrough-run-maturity.md` and `docs/verification/run-identity-proofs.md` only after the behavior is verified.

**Change:** Reuse the same read/classification preflight for both verified entry points, then apply `evidence_gate`, then execute or render. Preserve the explicit `GLEAMUNISON_STORE_ALLOW_UNVERIFIED` escape hatch and all trust checks for content that exists.

**Compatibility:** Existing content keeps the same evidence policy. Existing plain-text missing refs remain exit 2. JSON missing refs change from the incorrect exit 1 to the contractually correct exit 2.

**Regression proof:** The same all-zero or otherwise absent ref must produce `run_ref.Missing`, the missing-ref message, and CLI exit 2 in plain and `--json` modes, even when `GLEAMUNISON_EVIDENCE_SIGNING_KEY` is unset. Existing-key expiry, revocation, future activation, max-age, and allow-unverified tests must retain their current results.

**Rejected alternative:** Rewriting `cli_run.classify` or making JSON reinterpret `NoEvidence`. That would preserve the wrong ordering and create two definitions of “missing.”

**Command:** `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH; gleam test --target erlang -- --only run` (adapt the focused filter to the repository’s actual test runner); then clean-build and run both CLI forms with explicit `code=$?` capture.

### 2. Collapse DETS, manifest, and execution-log resolution into one store context — Medium

**Problem:** `--store`, `GLEAMUNISON_STORE_DIR`, `published`, package install, and execution logs do not all derive from one explicit context. `cli_pkg.gleam` carries its own `.gleamunison/store.dets` default, while publish/unpublish/purge resolve the manifest separately from the DETS path.

**Files:**

- Modify `src/gleamunison/cli_lifecycle.gleam` to own a resolved store context (store file, sibling manifest, log directory) or an equivalent data value.
- Modify `src/gleamunison/cli_run.gleam`, `cli_publish.gleam`, `cli_unpublish.gleam`, `cli_purge.gleam`, and `cli_pkg.gleam` to consume that context.
- Modify lifecycle, CLI, package, publish, unpublish, purge, and run integration tests.

**Change:** Resolve the root once at the command boundary. For a command-local `--store`, derive the sibling `published` index and log directory from the same path. Preserve the existing environment override and default path deliberately.

**Compatibility:** Default `.gleamunison` behavior and absolute `GLEAMUNISON_STORE_DIR` remain supported. A command that previously mixed roots will now operate consistently on the requested store; this is a correctness fix and may expose stale split state that operators must reconcile.

**Regression proof:** In a temporary isolated store, publish content, run it, unpublish/purge it, and install a package using the same explicit store root. Prove the default store has not changed. Include the package CLI path, not just top-level commands.

**Rejected alternative:** Add more per-command environment reads or a second manifest lookup helper. That preserves the split ownership that caused the defect.

**Command:** `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH; gleam test --target erlang`; then run the isolated-store end-to-end probe from outside the repository and capture all exit codes.

### 3. Make branch context explicit where the command contract requires it — Medium/Low

**Problem:** `run_ref.gleam`, `store_deps.gleam`, `cli_unpublish.gleam`, and `cli_purge.gleam` hard-code `main`, while `pkg install` can write a caller-selected branch. Name-ref dependency resolution can therefore inspect a different namespace from the one the operator selected.

**Files:**

- Modify `src/gleamunison/run_ref.gleam` and its callers/parser in `src/gleamunison/cli_run.gleam`.
- Modify `src/gleamunison/store_deps.gleam`, `cli_unpublish.gleam`, and `cli_purge.gleam`.
- Modify focused namespace and CLI tests plus help/README text.

**Change:** Carry a branch value into run/dependency/retraction operations. Keep `main` only as an explicit CLI default for backward compatibility; do not add hidden fallback between branches.

**Compatibility:** Existing invocations without `--branch` continue to use `main`. New invocations can target a non-main namespace and get deterministic resolution.

**Regression proof:** Install or bind a definition on a non-main branch, run a hash whose dependency is a name ref, and prove the selected branch—not `main`—is used. Prove missing branch bindings remain unresolved rather than falling through.

**Rejected alternative:** Keep `main` hidden and search all branches. That makes the same hash non-deterministic and turns namespace context into ambient state.

**Command:** `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH; gleam test --target erlang`; then run the non-main branch probe from a clean store.

### 4. Reconcile production trust configuration with the runbook — Medium

**Problem:** `trust.production_policy()` constructs exactly one `TrustedKey` from `GLEAMUNISON_EVIDENCE_SIGNING_KEY`, while `docs/operations/trust-and-key-rotation.md` documents multi-key overlap and removal.

**Decision gate:** First verify whether the repository has a required production multi-key input contract elsewhere. If no such contract exists, choose the smaller honest fix: narrow the runbook to one-key cutover semantics and clearly distinguish library-level multi-key tests from production configuration. Only implement multi-key environment parsing if the user explicitly wants that product surface and its security contract.

**Files for the default plan:** `docs/operations/trust-and-key-rotation.md`, relevant trust/evidence tests, and possibly a small README/config reference. Production trust code is not changed unless the decision gate finds a specified supported input format.

**Compatibility:** Existing one-key environment behavior remains unchanged. Documentation stops promising an operator workflow the CLI cannot perform.

**Regression proof:** The runbook’s commands and variables reproduce every production key state it claims. Library overlap tests remain clearly labeled as library policy tests.

**Rejected alternative:** Invent a delimiter, key-ID grammar, or implicit environment list without a product decision. Secrets and rotation semantics are not a place for guesswork.

**Command:** `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH; gleam test --target erlang -- --only trust`; run the documented production-policy probes in an isolated store without printing secrets.

## Documentation-only and design-risk handling

- Update `docs/walkthrough-run-maturity.md` and `docs/verification/run-identity-proofs.md` for the current `--json`/`--inspect` contract only after fix 1 passes. This is drift correction, not a separate runtime feature.
- Keep the README’s explicit statement that OS-level sandboxing is not implemented. If wording is ambiguous, clarify “bounded BEAM execution is not OS isolation”; do not build a process sandbox in this cycle.
- Keep hard-coded `main` as a documented compatibility default until branch context is implemented; do not describe it as arbitrary branch support.
- Preserve the existing audit as historical evidence. Write a follow-up re-audit with live exit codes rather than rewriting history to look green.

## Verification contract

1. Every changed production file is below 500 lines; test files are exempt.
2. Focused regressions pass after a clean build.
3. `gleam test` passes with zero failures and any warnings are reported rather than hidden.
4. The project verification gate passes with exit 0 and no pipe-masked failures.
5. The escript copied outside the repository can run against an explicitly isolated store and the store/manifest/log paths remain coherent.
6. `git diff --check` passes.
7. The re-audit names remaining high/medium findings. If any remain, the maturity loop continues; a green gate alone is not “full maturity.”

## Non-goals

- No OS/container sandbox implementation.
- No remote trust-policy distribution.
- No package protocol redesign.
- No push, release, deploy, publication, tag, or merge.
- No modification of `gleamunison_escript` or the pre-existing production-boundary witness.

## Rich Hickey recommendation

Fix the result-ordering defect first: it is one boundary, one test, and one owner. Then decide whether store and branch context are real command inputs before adding abstractions. The complecting alternative is a web of renderer-specific error translations and command-local path guesses; that is cleverness masquerading as architecture, and it will rot on contact with the next flag.
