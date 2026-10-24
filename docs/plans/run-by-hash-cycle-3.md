# Run-by-hash maturity cycle 3 plan

**Date:** 2026-10-24 EAT (UTC+3)
**Tracking:** Bankai `bk-45ad`
**Source audit:** `docs/audit/2026-10-24-run-by-hash-cycle-3.md`
**Status:** implementation plan for the smallest confirmed cycle-3 corrections.

## Goal

Make the public run-by-hash story match the current code without widening the runtime into an implicit network executor or inventing a production multi-key trust protocol. Cycle 3 has two documentation corrections and one carried implementation follow-up. The implementation is intentionally smaller than the audit surface: fix the claims that are wrong, preserve the boundaries that are deliberate, and give manifest effect metadata one durable owner (`bk-026d`).

## Confirmed findings and target state

### F1 — Production trust wording

`README.md` currently groups evidence signing, trust policy, and key rotation/revocation under one fully implemented/enforced capability. The shipped production environment accepts one configured signer with one validity/revocation window; `trust.TrustPolicy` can represent multiple keys only for library callers/tests. The README must distinguish:

- evidence signing is enforced at publish, package install, and run;
- the production environment exposes one signer and its validity/revocation controls;
- multi-key overlap is library-only until a separate operator configuration contract exists.

**Files:** `[MODIFY] README.md`.

### F2 — Local versus peer DAG resolution

`README.md` says DAG resolution fetches missing dependencies from peers during execution. `run` opens its selected local `StoreContext` and has no peer argument or network-fetch path. `sync` and `pkg --peer` are the explicit transfer commands. The README must say:

- `run` walks the selected local store and branch namespace;
- `sync` or `pkg --peer` must transfer missing content before `run`;
- a missing local ref is an unresolved execution result, not an implicit peer fetch.

**Files:** `[MODIFY] README.md`.

### F3 — Manifest effect flags

`pkg.publish_to_store_with_policy` receives effectful flags, but the manifest format stores only name/hash pairs and installation reconstructs every entry as pure. This is a real package-admission gap, but Bankai `bk-026d` already owns the format evolution and legacy parsing. Cycle 3 does not duplicate or partially implement it.

**Files:** none in this cycle; link `bk-026d` in the audit/re-audit and keep the package follow-up open.

### F4 — Test-count drift

`README.md` says 508 tests while the current clean cycle-2 receipt says 611. Do not replace the number until a fresh clean suite produces the receipt used for this cycle. Then update the README to the verified count and describe it as a current suite count, not a permanent promise.

**Files:** `[MODIFY] README.md` after verification.

## Implementation steps

1. **Redocument trust ownership.** Read the current README and replace only the capability-table wording that overstates production rotation/revocation. Preserve the detailed trust runbook and its one-signer cutover procedure.
2. **Redocument execution ownership.** Narrow the DAG-resolution paragraph and run examples so local execution and explicit peer transfer are separate commands. Do not add a peer flag to `run`.
3. **Run the clean suite before changing the count.** Use the pinned PATH, `gleam clean && gleam test`, and capture the actual pass/failure count and exit code. If the count differs from 611, use the new receipt rather than stale history.
4. **Refresh the README count.** Change only the stale suite count after the clean result is known. Keep the README version and capability claims otherwise unchanged.
5. **Verify the boundary.** Run format, compile, clean tests, diff check, the production-boundary gate, standalone artifact probes, and LOC checks. Inspect the generated witness; do not stage the pre-existing 2026-10-23 witness or `gleamunison_escript`.
6. **Re-audit.** Record the actual receipts, verify F1/F2/F4 are fixed, and explicitly carry F3 to `bk-026d`. Upload every changed Markdown file to Telegram topic `10282` after its edit.

## Regression and verification contract

- `grep`/source review must show the README no longer claims that `run` fetches peers implicitly.
- `grep`/source review must show production trust is described as one configured signer with library-only overlap.
- `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH; gleam format --check src test` exits 0.
- `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH; gleam check --target erlang` exits 0.
- `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH; gleam clean && gleam test` exits 0 with zero failures; the README count matches this run.
- `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH; git diff --check` exits 0.
- `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH; bb scripts/verify_production_boundaries.clj` exits 0 and reports every required gate passing.
- Standalone artifact and playbook receipts remain green; no command may silently mask its exit status with a pipe.
- `wc -l` confirms every changed production file remains below 500 LOC. This cycle should change documentation only.

## Explicit non-goals

- No OS/container executor or sandbox implementation. Same-VM bounded execution remains a documented non-claim.
- No automatic peer fetch in `run`; implicit network authority would be a new security and reproducibility boundary.
- No manifest format change in this cycle; `bk-026d` is the single owner for effect-flag propagation and legacy compatibility.
- No multi-key production trust grammar, secret delimiter, or zero-downtime rotation promise.
- No source changes to `cli_*`, `run_ref`, `store_deps`, `manifest`, or `pkg` unless verification discovers a regression directly caused by the documentation correction.
- No push, release, deploy, tag, publish, merge, or changes to `gleamunison_escript` / the pre-existing 2026-10-23 witness.

## Rejected complecting alternatives

- **Add a `--peer` flag to `run`:** rejected; it would merge execution, network admission, and trust decisions into one command before the product has specified a peer/evidence contract.
- **Implement manifest effect flags here:** rejected; two beads would own one format migration and legacy parsing would become ambiguous.
- **Claim multi-key rotation from the library type:** rejected; library expressiveness is not an operator configuration surface.
- **Keep the stale test count:** rejected; a release document must name a live receipt, not a historical number.

## Rich Hickey recommendation

Narrow the prose instead of expanding the runtime: local data stays local, explicit transfer stays explicit, and manifest evolution has one owner. The rejected alternatives complect authority with convenience; the smallest truthful surface survives scrutiny better than a larger feature list.
