# Audit — run-by-hash execution path

**Date:** 2026-10-23 (EAT)
**Scope:** `gleamunison run <content-hash>` and the adjacent store, evidence, namespace, package, loader, and runtime-boundary seams.
**Tracking:** Bankai `bk-8320`
**Method:** source inspection plus a built-escript probe; production code was not changed for this audit.

## Executive finding

The run-by-hash path has a sound content-addressed read path and a useful plain-text exit-code contract, but its JSON path violates that contract for an absent ref. `run --json` calls `run_verified_raw`, which enters the evidence gate before it performs the existence/read check. With no production signing key, an all-zero absent ref therefore exits **1** with `is not verified`, while the plain command exits **2** with `not in the store`. The same hash does not have one failure classification.

The maturity walkthrough and identity-proof document also describe an older JSON behavior that the current implementation explicitly rejects: the docs say JSON on a function inspects it without calling, while the code makes `--inspect` the non-executing mode and `--json` always executes. The trust-rotation runbook describes a multi-key environment policy, but production policy currently constructs exactly one key from one environment secret. Finally, the CLI's `--store` override is not consistently one store boundary: `run` derives its log directory from the override, while publish/unpublish/purge resolve the manifest path from `GLEAMUNISON_STORE_DIR` and the package CLI has a separate hard-coded `.gleamunison/store.dets` default.

These findings are not claims that the whole runtime is unsafe. The audit separates confirmed defects from documentation drift, design risks, and claims checked and not substantiated.

## Severity-ranked findings

### F1 — High: `run --json` masks an absent ref as an evidence refusal

**Status:** confirmed defect.

**Evidence:**

- `src/gleamunison/run_ref.gleam` checks existence in `run_verified` before `evidence_gate`, but `run_verified_raw` begins with `evidence_gate` and only then calls `execute`.
- `src/gleamunison/cli_run.gleam` dispatches JSON to `run_ref.run_verified_raw`; plain output dispatches to `run_ref.run_verified`.
- `classify` correctly maps `Missing` to exit 2, but JSON never reaches `Missing` when the evidence gate refuses first.
- Live probe against the built `./gleamunison_escript` on 2026-10-23 EAT, using the absent all-zero SHA-256 ref:

  - `run <zero-ref>` → exit **2**, stderr `not in the store: ... (publish it or sync it first)`.
  - `run --json <zero-ref>` → exit **1**, stderr `... is not verified: evidence: GLEAMUNISON_EVIDENCE_SIGNING_KEY is required for production verification`.

**Impact:** scripts cannot treat the hash as the primary lookup key consistently. A missing object can be reported as a trust-policy problem, and operators may waste time configuring evidence for content that does not exist. The defect is especially visible in a fresh production environment where the missing-key refusal is deterministic.

**Recommended correction:** make every execution entry point settle content existence/read integrity before the evidence gate, including the raw/JSON path. Add a CLI regression that runs the same absent ref through plain and JSON modes and asserts exit 2 plus the missing-ref message. This audit intentionally does not implement the correction.

### F2 — Medium: store override and package/index ownership are split across incompatible roots

**Status:** confirmed design defect / operational risk.

**Evidence:**

- `cli_run` accepts `--store path` and passes `store_dir(store_path)` to execution logging, so its store and `exec_log.dets` follow the explicit path.
- `cli_publish` resolves its store path from `cli_lifecycle`, then separately calls `resolve_manifest_path`; that function derives `published` from `GLEAMUNISON_STORE_DIR`, not from a command-local path argument.
- `cli_unpublish` and `cli_purge` accept a store override for the DETS store but resolve their manifest path independently through `resolve_manifest_path`.
- `cli_pkg.gleam` uses a separate `const default_store = ".gleamunison/store.dets"` and its install/publish flows do not share the lifecycle resolver used by `run` and the top-level publish/unpublish/purge commands.
- The comments in `cli_lifecycle` claim the manifest is derived from the resolved store directory, but that does not make a `--store` path and its sibling `published` index a single explicit boundary in commands that carry both concepts separately.

**Impact:** an operator can point a command at one DETS file while name/index operations read or write another directory's `published` file. The resulting state can look like an empty package registry, leave an index and store out of sync, or make a command appear to retract content that belongs to a different store. The package CLI can also use a different default from the top-level lifecycle path.

**Recommended correction:** define one store context value containing the resolved store file, sibling index, and log paths; pass it into commands rather than resolving each path independently. Make `pkg` use the same resolver. Add end-to-end tests that use only `--store` and prove publish → run → unpublish/purge and package install all observe the same directory. This audit intentionally does not implement the correction.

### F3 — Medium: the documented multi-key rotation procedure cannot be performed by the production CLI

**Status:** confirmed documentation/implementation mismatch with a real operational limitation.

**Evidence:**

- `docs/operations/trust-and-key-rotation.md` documents an ordered policy with multiple trusted keys, overlap, and removal of the old key.
- `src/gleamunison/trust.gleam` defines a multi-key `TrustPolicy` and tests overlap in memory, but `production_policy()` calls `evidence.production_signer()` once and constructs `RequireKeys([TrustedKey(signer, state)], max_age)`: production configuration has exactly one signer/key entry.
- `src/gleamunison/evidence.gleam` defines the only production signer as `env:GLEAMUNISON_EVIDENCE_SIGNING_KEY`; there is no production parser for a list of key IDs/secrets or per-key windows.
- The documented variables `_KEY_SINCE`, `_KEY_UNTIL`, and `_KEY_REVOKED` alter the one configured signer; they do not express an old and new signer simultaneously. The overlap tests exercise the library constructor, not the CLI environment surface.

**Impact:** a zero-downtime overlap rotation as documented cannot be configured through the production environment. Replacing the secret changes the signer identity and there is no way for one production policy to accept both signer IDs during overlap. An operator must choose between a cutover that may reject old records and retaining the old secret, contrary to the runbook's stated procedure.

**Recommended correction:** either implement a real multi-key production configuration and test it through the CLI, or narrow the runbook to the actual one-key semantics and document the cutover limitation honestly. Do not leave the library fixture capability presented as an operator capability. This audit intentionally does not implement the correction.

### F4 — Medium: bounded runtime execution is not the same as an untrusted-code sandbox

**Status:** confirmed boundary / design risk, not a newly discovered bypass.

**Evidence:**

- `README.md` correctly classifies the service as authenticated single-node and says OS/container isolation for untrusted code is not implemented.
- `src/gleamunison/sandbox_policy.gleam` refuses the `untrusted-execution` profile without an external executor and denies direct host FFI/native jets for that policy.
- `src/gleamunison_repl_ffi.erl` executes `call_eval` in a BEAM worker with timeout/reduction-related scope handling, but it invokes the compiled module in the same Erlang VM and its default effect handlers include console, state, remote-node, and LLM behavior for the general evaluator.
- `run_ref` calls `call_eval` directly; it does not accept or apply a `SandboxPolicy` or an external executor. The `sandbox_policy` module is not referenced by the run-by-hash seam in the source search.

**Impact:** the run command must not be treated as an untrusted-code boundary. Timeouts and resource bounds reduce runaway work, but they do not provide OS isolation or make host authority disappear. This is a design risk only where deployment or documentation treats `run` as a sandbox; the current README's explicit non-claim is accurate.

**Recommended correction:** keep the deployment classification explicit and ensure any future untrusted run route composes the same policy admission with an external executor before evaluation. Do not advertise the bounded BEAM scope as isolation. No code change was made in this audit.

### F5 — Low/Medium: mutable branch choice is hard-coded in the run and lifecycle-adjacent dependency logic

**Status:** confirmed limitation / design risk.

**Evidence:**

- `run_ref.gleam`, `store_deps.gleam`, `cli_unpublish.gleam`, and `cli_purge.gleam` hard-code `main` as the branch used for name resolution, dependent analysis, and retraction.
- `cli_pkg` can install onto a caller-selected branch, but the run resolver still reads `main`.
- The content hash remains the execution identity, but definitions whose dependencies are name refs need the current branch namespace to map those names to content refs.

**Impact:** a package or namespace installed on a non-`main` branch is not the namespace that `run <hash>` resolves. A hash can therefore be present and verified while its name-based dependency closure is unavailable or resolves against a different branch. This is not a hash-integrity failure; it is a branch-context API omission.

**Recommended correction:** make branch context explicit for run and dependency/retraction operations, with an intentional default only at the CLI boundary. Add a non-`main` branch end-to-end proof. This audit intentionally does not implement the correction.

## Documentation drift

### D1 — The run maturity walkthrough is stale about `--json`

`docs/walkthrough-run-maturity.md` says `run --json <hash>` on a function reports what it is and “does not execute.” The current implementation and CLI usage say the opposite: `--json` always executes and `--inspect` is the only non-executing mode. The same walkthrough's sample exit-code table lists `run --json <hash>` as a successful inspection path. The code change that established the current semantics is commit `78d3f9e` (`--json always executes, --inspect reports without calling`), so this is not an ambiguous interpretation; the walkthrough was not refreshed after the behavior changed.

### D2 — The identity-proof document repeats the stale JSON claim

`docs/verification/run-identity-proofs.md` lists `--json` on a function as exit 0 with a JSON line and no execution. That claim contradicts `cli_run.render_output`, `run_ref.run_verified_raw`, and the current usage text. The document also says the whole proof is re-runnable but its command examples do not exercise the current `--inspect` behavior or the JSON missing-ref ordering defect.

### D3 — README version, counts, and witness link are stale relative to the current witness

`README.md` still names version `3.24.0`, 508 tests, and the 2026-10-21 witness, while the current 2026-10-23 production-boundary witness is headed by `50eef0a` and records a different gate run. The README may intentionally describe the last release rather than the working tree, so this is documentation drift rather than a runtime defect; it should nevertheless be labeled as release/current-tree scope instead of presenting both as one measured state.

### D4 — The trust runbook overstates production rotation capability

The runbook's multi-key policy and overlap procedure are valid for the library-level `TrustPolicy` constructors and tests, but not for `trust.production_policy()` as currently configured by environment. The distinction between fixture/library policy and production policy needs to be explicit.

## Ruled-out or not-confirmed claims

- **Hash integrity is not the defect:** `codebase.get` re-verifies stored bytes against the requested ref, and `manifest.fetch` re-hashes manifest content. The audit found no evidence that a normal store read accepts bytes under the wrong content hash.
- **Plain-text missing-ref classification is not the defect:** the live plain `run` probe returned exit 2 and the missing-ref message as documented. The defect is the JSON ordering divergence.
- **`--json` executing is not itself a defect:** the current source deliberately defines JSON as execution output and provides `--inspect` for non-executing introspection. The defect is stale documentation and the inconsistent absent-ref gate order.
- **Trust overlap logic is not absent in the library:** `trust_policy_test.gleam` covers multi-key overlap and `verified_at` can select an older admissible record. The finding is that production environment construction exposes one key, not that the pure policy logic cannot represent overlap.
- **The untrusted profile is not silently enabled:** `admit_profile("untrusted-execution")` constructs it without an external executor and refuses it. The run-by-hash path simply does not call that policy surface.
- **No production source was changed during this audit.** The working tree was already dirty in `docs/verification/production-boundaries-2026-10-23.md` and the user-owned `gleamunison_escript`; those were preserved and are not part of this audit document.

## Verification record

All timestamps below are **EAT (UTC+3)**. The audit was written on 2026-10-23 EAT.

- `git status --short`, `git log --oneline -8`, and `git branch --show-current`: branch `main`; pre-existing modifications were the production-boundary witness and `gleamunison_escript`.
- `bankai_query action=doctor`: healthy; 604 tasks, 1,197 versions, zero cycles and zero missing targets.
- `git diff --check`: passed before writing this document.
- Built-escript absent-ref probe: plain mode exit 2; JSON mode exit 1 under the same absent all-zero ref.
- Source probes: `grep` confirmed `run_verified_raw` is the JSON path, hard-coded `main` appears in the run/dependency/retraction seams, and `sandbox_policy` has no caller in `src/gleamunison`.
- The current witness records all listed gates at exit 0, but it is a witness for commit `50eef0a`, not proof that the audit findings are fixed. The witness itself is a pre-existing modified file and was not rewritten here.

## Rich Hickey certification

The audit keeps one fact per seam and refuses the tempting abstraction of “maturity” as a single green label: content identity, evidence admission, namespace context, and runtime authority are different data. The smallest honest next step is to fix the JSON ordering and then make store/branch context explicit; adding more compatibility prose without those owners would only complect the lie.
