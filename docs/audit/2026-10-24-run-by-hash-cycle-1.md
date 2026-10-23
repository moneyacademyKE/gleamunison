# Re-audit — run-by-hash maturity cycle 1

**Date:** 2026-10-24 EAT (UTC+3)
**Tracking:** Bankai `bk-ac11`; fix commit `78e669e`
**Scope:** `run <content-hash>` plain and JSON execution, evidence ordering, current verification gate, and the previously reported boundary findings.

## Verdict

The high-severity JSON missing-reference defect is fixed. A clean build and the rebuilt escript now classify the same absent all-zero SHA-256 ref identically:

- plain `run <zero-ref>`: exit **2**, `not in the store: ...`;
- `run --json <zero-ref>`: exit **2**, the same missing-ref message.

The fix is a shared preflight in `src/gleamunison/run_ref.gleam`: both `run_verified` and `run_verified_raw` read and classify the requested content before invoking the evidence policy. A regression test now pins the raw/JSON path, alongside the existing plain-path test. Existing content still reaches the evidence gate after preflight.

The code and focused tests are not fully mature yet. The medium findings from the previous audit remain open and were not silently converted into “done” merely because the gate is green: store/manifest context is still split, production configuration still exposes one trust key while the runbook describes multi-key overlap, and branch resolution still defaults internally to `main`. Documentation drift about JSON/inspection was corrected in the walkthrough and identity-proof document.

## Finding status

### F1 — High: JSON absent-ref classification

**Status:** fixed and re-proven.

**Implementation:** commit `78e669e`, `src/gleamunison/run_ref.gleam`, shared `preflight` called by both verified entry points.

**Regression:** `test/run_ref_test.gleam` → `raw_absence_is_reported_before_evidence_test`; existing `absence_is_reported_before_evidence_test` covers plain output.

**Live evidence after a clean build:**

```text
plain_exit=2
not in the store: 0000000000000000000000000000000000000000000000000000000000000000 (publish it or sync it first)
json_exit=2
not in the store: 0000000000000000000000000000000000000000000000000000000000000000 (publish it or sync it first)
```

The test suite previously passed at 607 tests with zero failures. The integrated boundary gate also passed all 15 batteries after the change.

### F2 — Medium: store, manifest, package, and log context

**Status:** open; not addressed in cycle 1.

`cli_run` can use a command-local `--store`, while package and manifest paths retain separate resolution logic. The earlier audit evidence remains valid. This is the next production boundary fix because a command can still address a DETS store and a sibling name index through different resolution paths.

### F3 — Medium: production trust configuration versus multi-key runbook

**Status:** open; intentionally not addressed in cycle 1.

`trust.production_policy()` still constructs one `TrustedKey` from the production environment signer. The library can represent multiple keys, but the documented overlap procedure is not yet an operator-configurable production surface. The next action is to narrow the runbook unless a separately approved multi-key input contract is chosen.

### F4 — Medium: bounded BEAM execution versus OS isolation

**Status:** design boundary, not a new bypass; remains intentionally out of scope.

The README and witness correctly refuse to call same-VM timeout/reduction limits an OS sandbox. No process isolation was added in this cycle. The run-by-hash maturity loop must retain this non-goal unless the user requests a separate runtime-architecture project.

### F5 — Low/Medium: branch context

**Status:** open limitation; not addressed in cycle 1.

The run and dependency/retraction seams still use `main` internally. The plan records explicit branch context as a later bounded change, with `main` retained only as a compatibility default until that interface is implemented.

## Documentation status

- `docs/walkthrough-run-maturity.md` now says `--json` always executes and `--inspect` is the only non-executing mode; its exit table distinguishes JSON arity refusal from inspection.
- `docs/verification/run-identity-proofs.md` now uses `--inspect` for the no-execution proof and describes JSON with supplied arguments as the execution renderer.
- `docs/operations/trust-and-key-rotation.md` remains stale about the production multi-key surface and is deliberately not rewritten until the trust configuration decision is made.
- `README.md` and the pre-existing 2026-10-23 witness were not rewritten in this cycle. The 2026-10-24 gate generated a new witness; it is evidence for this run, not proof that the open medium findings are fixed.

## Verification record

All timestamps are EAT (UTC+3).

- `gleam clean && gleam test`: exit **0**, **607 passed, 0 failures**.
- `bb scripts/verify_production_boundaries.clj`: exit **0**, **15/15 gates PASS**, including format, diff check, suite, escript, artifact, CLI truth, HTTP boundary, release/upgrade contracts, playbook, and auxiliary probes.
- Rebuilt escript absent-ref probe: plain exit **2**, JSON exit **2**, identical missing-ref classification.
- `gleam format --check` and `git diff --check`: exit **0**.
- Changed production file line count: `src/gleamunison/run_ref.gleam` is **392 lines**, below the 500-line ceiling. The changed test file is exempt.
- No push, release, deploy, publish, or tag was performed.

## Next loop

Cycle 2 should address F2 first: create one explicit store context and prove isolated-store publish/run/unpublish/purge/package behavior. Then make the trust runbook honest about one-key production configuration before deciding whether branch context deserves a separate API change. Do not bundle OS sandboxing into either fix.

## Rich Hickey certification

The first fix deletes a contradiction rather than adding a renderer exception: one preflight, one missing-content classification, two output renderers. The gate proves the change is small and composable; the remaining findings are still named because a green battery is not permission to pretend the store and trust boundaries are already one thing.
