# Re-audit — run-by-hash maturity cycle 3

**Date:** 2026-10-24 EAT (UTC+3)
**Tracking:** Bankai `bk-45ad`
**Scope:** Remaining run-by-hash/store boundaries after cycle 2: package manifest admission, branch/store propagation, trust and sandbox claims, release evidence, and operator documentation.
**Method:** Fresh source, test, script, and documentation inspection on `main`; this audit records verified facts only. No push, release, deploy, tag, publish, or merge is part of the audit.

## Verdict

Cycle 2 closed the audited store-context and branch-selection defects. Cycle 3 finds two confirmed documentation-contract defects and one implementation follow-up that is already represented by an open Bankai bead:

- **F1 — Medium, documentation drift:** `README.md` says evidence signing, trust policy, and key rotation/revocation are “implemented and enforced at `publish`, `pkg install` and `run`”, but the same repository documents that `trust` is library-only and the production policy accepts one configured signer. The wording overstates production rotation/revocation. The trust runbook is more accurate; the README capability table is not.
- **F2 — Medium, documentation drift:** `README.md` says `sync` pulls missing dependencies during the run-by-hash DAG resolution, but the `run` CLI path resolves only against the local store/namespace. Peer transfer is explicit in `sync`/`pkg --peer`; `run` has no peer argument or network fetch path. This makes a documented execution step sound more automatic than the code.
- **F3 — Medium, implementation follow-up:** package manifests serialize only `(name, hash)` definition entries while `pkg.publish_to_store_with_policy` receives effectful flags and `pkg.install_from_store_with_policy` therefore gates every manifest definition as pure (`False`). The open Bankai bead `bk-026d` already tracks carrying per-definition effect flags through the manifest format. This cycle should not duplicate that work; it should preserve the finding and link the bead.
- **F4 — Low, release metadata drift:** README headline counts still say 508 tests while the current cycle-2 evidence records 611. This is not an execution blocker, but it weakens the release claim and should be corrected with the next documentation landing.

The bounded same-VM BEAM evaluator remains explicitly not an OS/container sandbox. That is an intentional non-goal, not a newly discovered bypass.

## Evidence

### F1 — README overclaims production trust rotation (Medium)

- `README.md:32-36` labels “Evidence signing, trust policy, key rotation/revocation” as implemented and enforced at all three CLI surfaces.
- `README.md:229-240` says `gleamunison/trust` is library-only and that `evidence` verifies against a configured signer without consulting a rotation policy.
- `docs/operations/trust-and-key-rotation.md` states production supports one configured signer at a time; multi-key overlap is library/test behavior, not an operator configuration.
- `src/gleamunison/trust.gleam` contains the policy model, but the production environment parser constructs one signer. The code and runbook support a narrower claim than the capability table.

**Impact:** An operator reading the capability table can infer production key overlap/revocation support that is not configurable through the shipped environment contract.

**Smallest correction:** change the README state to “evidence signing enforced; single-signer validity window/revocation flags supported; multi-key rotation is library-only.” Keep the runbook as the detailed source.

### F2 — README overstates automatic peer fetch during `run` (Medium)

- `README.md:104-107` says DAG resolution “fetches missing dependencies from peers over the sync protocol”.
- `src/gleamunison/cli_run.gleam` resolves a local `StoreContext`, opens its local DETS adapter, and calls `run_ref` with no peer parameter.
- `src/gleamunison/run_ref.gleam` resolves definitions from the selected adapter and branch namespace; an absent ref becomes a typed unresolved result. There is no `sync` or peer call in this path.
- `src/gleamunison/cli_sync.gleam` and `src/gleamunison/cli_pkg.gleam` expose explicit peer transfer; that is separate from `run`.

**Impact:** A user can reasonably expect `run` to retrieve a missing dependency, but the command refuses when the local store lacks it. The implementation is safer than the wording; the wording needs narrowing.

**Smallest correction:** say that DAG resolution walks the local store, while `sync` or `pkg --peer` must fetch missing content before `run`.

### F3 — Manifest effect flags are dropped (Medium, tracked implementation follow-up)

- `src/gleamunison/pkg.gleam:280-296` receives `List(#(String, String, Bool))`, checks the real flags through `turnstile.check_with_policy`, then stores `manifest.add_def(m, d.0, d.1)` and drops `d.2`.
- `src/gleamunison/manifest.gleam:20-32` defines manifest entries as `(definition name, hash hex)` with no effect flag.
- `src/gleamunison/pkg.gleam:217-235` reconstructs all install entries as `#(d.0, d.1, False)`, so effectful definitions installed from a manifest cannot use the Io attestation branch.
- Bankai `bk-026d` is open with the exact required format evolution and legacy-parse requirement.

**Disposition:** Do not implement in this cycle. Link the existing bead rather than creating a second owner. If that bead is completed later, update the package tests and production gate before calling package admission mature.

### F4 — README test count drift (Low)

- `README.md:10-12` says `508 tests, 0 failures`.
- Cycle-2 re-audit records `gleam clean && gleam test` at 611 passed, 0 failures.
- The current source tree contains the cycle-2 regression suites, so the old count is not a current release receipt.

**Disposition:** Correct the count only after a fresh clean suite, so the documentation names a live receipt rather than copying cycle-2 history.

## Boundary decisions retained

- **OS isolation:** `README.md`, `docs/operations/deployment-profiles.md`, and `src/gleamunison/sandbox_policy.gleam` correctly refuse to call bounded BEAM execution an OS sandbox. No change is justified by this audit.
- **Branch context:** cycle 2’s explicit `--branch` path is present in `run`, `unpublish`, `purge`, and dependency helpers. `publish` remains deliberately on `main`; widening publish branch selection is not required to correct the run-by-hash contract here.
- **Store context:** the cycle-2 `StoreContext` is used by the audited CLI paths. No new competing `store.dets` resolver was found in the current source grep; the remaining hard-coded `main` constants are explicit compatibility/default choices, not hidden store selection.
- **Production trust:** the runbook’s one-signer contract is the authority for operator configuration until a separate multi-key API is specified.

## Cycle-3 plan boundary

1. Correct the README trust and peer-fetch claims, and refresh the test count only after clean verification.
2. Do not duplicate `bk-026d`; carry its manifest-format finding into the next maturity queue.
3. Run clean tests, the production-boundary gate, LOC/diff checks, and the standalone artifact probe.
4. Re-audit the resulting documentation and leave package effect-flag propagation as an explicit tracked follow-up.

## Rich Hickey certification

The smallest truthful repair is to narrow prose to the code that owns the behavior: local DAG execution stays local, the one-signer production contract stays one-signer, and manifest effect metadata gets one future owner (`bk-026d`) instead of a second half-fix. Less magic, fewer promises, no new protocol-shaped furniture.

## Final verification and re-audit — 2026-10-24 EAT

The planned corrections landed in `37e7843` (`docs: clarify run-by-hash boundaries (bk-45ad)`). Fresh verification confirms the documentation now matches the implementation:

- **F1 fixed:** the README names evidence signing and the single-signer validity/revocation policy as enforced, and explicitly labels multi-key overlap library-only.
- **F2 fixed:** the README says `run` resolves the selected local store/branch and that `sync` or `pkg --peer` must transfer missing content first; `run` does not fetch peers implicitly.
- **F4 fixed:** the README now records **611 passing, 0 failures**, matching the clean suite and command example.
- **F3 remains open by design:** manifest effect flags are still owned by `bk-026d`; no duplicate implementation was introduced.

### Verification receipts

- `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH; gleam clean && gleam test` — exit 0; **611 passed, 0 failures**.
- `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH; gleam format --check src test` — exit 0.
- `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH; gleam check --target erlang` — exit 0; one pre-existing unused `None` import warning in `test/sync_accept_test.gleam`.
- `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH; bb scripts/verify_production_boundaries.clj` — exit 0; **15/15 gates PASS**. Playbook: **934 passed, 0 failed, 238 excluded**. Artifact: version `3.24.0`, 13 Datalog engine modules, 0 test modules.
- `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH; git diff --check` — exit 0.
- All changed production files remain below the 500-line ceiling; this cycle changed only `README.md` in production documentation terms.

The gate generated `docs/verification/production-boundaries-2026-10-24.md` for the current `main` at `37e7843`. The pre-existing `docs/verification/production-boundaries-2026-10-23.md` edit and `gleamunison_escript` remain excluded from the cycle commit. No push, release, deploy, tag, publish, or merge occurred.

## Final Rich Hickey certification

Cycle 3 deleted two misleading promises instead of adding runtime machinery: local execution stays local, production trust stays one-signer, and manifest evolution has one owner. The only remaining medium finding is named, tracked, and unpretended; that is maturity without decorative complexity.