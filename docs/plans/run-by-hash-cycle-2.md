# Run-by-hash maturity cycle 2 plan

**Date:** 2026-10-24 EAT (UTC+3)
**Tracking:** Bankai `bk-5296`
**Source audit:** `docs/audit/2026-10-24-run-by-hash-cycle-2.md`
**Status:** implementation plan; no production code is changed by this document.

## Goal

Remove the remaining confirmed boundary inconsistencies without inventing a new trust protocol or pretending the BEAM evaluator is an OS sandbox. The cycle has one primary production fix (one store context), one explicit API-context fix (branch data), and one documentation correction (trust runbook). Each change gets its own regression proof and atomic commit.

## Design rules

- Resolve paths once and pass data. Do not let each command read `GLEAMUNISON_STORE_DIR` independently.
- Treat a branch name as an execution input, not a hidden global constant.
- Preserve `main` as the explicit default for compatibility, but never search all branches or silently fall back.
- Keep `TrustPolicy` library expressiveness separate from the production environment contract. Do not invent a delimiter or key-ID grammar for secrets.
- Keep bounded same-VM BEAM execution separate from OS/container isolation; the latter is not part of this cycle.
- Never stage `gleamunison_escript` or the pre-existing 2026-10-23 witness edit.

## Change 1 — one resolved store context (F2, Medium)

### Current defect

`--store` can choose the DETS file while manifest resolution still follows `GLEAMUNISON_STORE_DIR`. `cli_pkg.gleam` carries an independent `.gleamunison/store.dets` default. Execution logs follow the run path, while content and name indexes are resolved elsewhere.

### Target ownership

`src/gleamunison/cli_lifecycle.gleam` owns a small immutable `StoreContext` value containing:

- `store_path` — the DETS file;
- `manifest_path` — sibling `published` index;
- `root_dir` — the directory used by content and execution logs.

The resolver accepts an optional command-local store path. If supplied, it validates the path and derives all siblings from it. If absent, it reads `GLEAMUNISON_STORE_DIR` once and derives the same values. The default remains `.gleamunison/store.dets`.

### Files

- Modify `src/gleamunison/cli_lifecycle.gleam` to define and resolve the context.
- Modify `src/gleamunison/cli_run.gleam`, `cli_publish.gleam`, `cli_unpublish.gleam`, `cli_purge.gleam`, `cli_pkg.gleam`, `cli_evidence.gleam`, `cli_log.gleam`, and `cli_sync.gleam` to consume the context where they currently resolve sibling paths separately.
- Modify lifecycle and command integration tests; add an isolated-store regression that exercises explicit store path plus sibling manifest/log paths.

### Compatibility

- `GLEAMUNISON_STORE_DIR=/absolute/root` continues to select `/absolute/root/store.dets`, `/absolute/root/published`, and `/absolute/root/*_log.dets`.
- `--store /absolute/root/store.dets` selects the same sibling files even when `GLEAMUNISON_STORE_DIR` points elsewhere.
- A bare command without overrides keeps `.gleamunison` behavior.
- Existing manifest files are not migrated or deleted; the corrected resolver simply stops reading the wrong root.

### Regression proof

In one clean temporary workspace:

1. Put a known name/hash line in `explicit/published`.
2. Set `GLEAMUNISON_STORE_DIR` to a different `environment` root.
3. Run `unpublish name --store explicit/store.dets`; it must read `explicit/published`, not `environment/published`.
4. Run package install/publish with the same explicit root and prove its DETS and manifest reads stay inside `explicit`.
5. Prove the run execution log is beside the selected store and the default/environment root is unchanged.

### Rejected alternative

Do not add `resolve_manifest_path_for(store_path)` beside the old environment resolver and call it selectively. That creates two valid APIs and leaves future commands free to choose the wrong one. One context, one resolver.

## Change 2 — explicit branch context (F5, Low/Medium)

### Current defect

`run_ref`, `store_deps`, `unpublish`, and `purge` hard-code `main`; package install accepts `--branch`. A name-ref dependency bound on another branch is invisible to run and retraction.

### Target ownership

Carry a branch string from the CLI boundary into run/dependency/retraction functions:

- `cli_run` parses optional `--branch`, defaulting explicitly to `main`.
- `run_ref` accepts `branch` and passes it into name-ref resolution.
- `store_deps` functions accept `branch` instead of reading a module constant.
- `cli_unpublish` and `cli_purge` parse `--branch`, default to `main`, and pass it to dependency/name/unbind operations.
- `cli_publish` may remain `main` in this cycle unless the audit proves publish branch selection is part of the user-facing contract; do not widen scope just to remove every literal.

### Files

- Modify `src/gleamunison/cli_run.gleam`, `run_ref.gleam`, `store_deps.gleam`, `cli_unpublish.gleam`, and `cli_purge.gleam`.
- Modify focused run, store-deps, namespace, and CLI parser tests.
- Update README/help and run identity documentation to state the default and branch flag.

### Compatibility

- Existing invocations without `--branch` retain `main` behavior.
- Existing library callers must receive a deliberate default or a new explicit argument in one atomic signature/caller change; no overloaded hidden global.
- A missing selected branch returns the existing missing-namespace behavior; it never falls through to `main`.

### Regression proof

Use an in-memory or isolated store with two branches: bind the same name to different content on `main` and `release`, then run a root with a name-ref dependency under each branch. Assert each selects its own binding. Run a dependency/retraction check under `release` and assert it sees only `release` bindings.

### Rejected alternative

Do not scan all branches or choose the branch with the newest head. That turns a reproducible command into ambient state and makes content-hash execution non-deterministic.

## Change 3 — make trust rotation documentation honest (F3, Medium)

### Current defect

`trust.production_policy()` supports one signer from `GLEAMUNISON_EVIDENCE_SIGNING_KEY` plus one key window/revocation state. The runbook describes multi-key overlap that only the library-level `TrustPolicy` constructors can represent.

### Target behavior

Keep production code unchanged in this cycle. Rewrite `docs/operations/trust-and-key-rotation.md` so it says:

- the shipped environment config is one active signer at a time;
- `KEY_SINCE`, `KEY_UNTIL`, `KEY_REVOKED`, and `MAX_AGE` govern that signer;
- replacing the secret is a cutover, not an overlap;
- multi-key overlap is currently a library-policy capability and requires a separately specified production configuration before operators can use it;
- revocation/expiry behavior and evidence identity remain as currently implemented.

Add a short operator-safe cutover procedure that does not claim zero-downtime overlap. Do not print or store secrets.

### Files

- Modify `docs/operations/trust-and-key-rotation.md`.
- Add or adjust a documentation-focused trust test only if an existing command claim needs a runnable proof; do not alter production trust code without an explicit multi-key product decision.

### Compatibility

No runtime behavior changes. The change removes an impossible promise and labels library tests correctly.

### Rejected alternative

Do not invent `KEYS=...`, comma-separated secrets, or implicit signer IDs. Secret parsing and key overlap are a security API, not a harmless convenience flag.

## Explicit non-goal — runtime sandbox

Do not change `src/gleamunison_repl_ffi.erl` or the sandbox policy solely to make the maturity label sound stronger. Same-VM timeout/reduction limits are bounded execution, not OS/container isolation. The README and production-boundary witness should continue to say so.

## Verification contract

1. `gleam format --check src test` exits 0.
2. `gleam clean && gleam test` exits 0 with zero failures.
3. Focused store-context tests prove explicit `--store` controls DETS, manifest, and logs together.
4. Focused branch tests prove non-main execution and retraction without fallback.
5. Trust documentation commands and variables match the one-key production policy; no secret is printed.
6. `bb scripts/verify_production_boundaries.clj` exits 0 and reports all required gates passing.
7. The rebuilt escript works outside the repository against an isolated store.
8. Every changed production file remains below 500 LOC; Markdown docs remain readable and are uploaded after each edit.
9. A dated re-audit records which findings are fixed, which remain, and why any remaining risks are out of scope.

## Atomic commits and stop boundary

- Commit the store-context change separately from branch-context and trust-documentation changes, each referencing `bk-5296`.
- Commit the audit/plan/re-audit docs separately from production fixes when practical.
- Stage only cycle-2 files. Do not commit the user escript or the unrelated 2026-10-23 witness edit.
- Do not push, publish, tag, release, deploy, or merge.

## Rich Hickey recommendation

The simplest repair is not a clever resolver; it is data made explicit once. A `StoreContext` and a branch string remove more ambiguity than a pile of command-local helpers. For trust rotation, deleting the impossible overlap promise is safer than building a secret grammar before the product has chosen one.
