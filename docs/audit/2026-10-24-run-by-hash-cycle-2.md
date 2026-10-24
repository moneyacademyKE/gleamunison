# Re-audit — run-by-hash maturity cycle 2

**Date:** 2026-10-24 EAT (UTC+3)
**Tracking:** Bankai `bk-5296`; source audit `docs/audit/2026-10-24-run-by-hash-cycle-2.md`
**Scope:** Store/manifest/log resolution, branch context, production trust configuration, and the run-by-hash CLI contract.
**Method:** Fresh source inspection after implementation, clean-build verification, focused regressions, the integrated production-boundary gate, and live CLI probes. No push, release, deploy, publish, or merge occurred.

## Verdict

The cycle-2 findings are fixed. No confirmed high or medium blocker remains in the audited run-by-hash boundary.

- **F2 — fixed:** one `StoreContext` now owns the selected DETS path, sibling `published` manifest, and log root. Explicit `--store /absolute/path/store.dets` and `GLEAMUNISON_STORE_DIR=/absolute/root` enter the same resolver. `run`, `publish`, `unpublish`, `purge`, `pkg`, `evidence`, `log`, `sync`, and `test` no longer invent competing sibling roots.
- **F3 — fixed as documentation:** the production runbook now says one configured signer at a time; multi-key overlap is explicitly library-policy/test behavior until a production configuration contract is approved. No undocumented secret grammar was added.
- **F5 — fixed:** `run`, `unpublish`, and `purge` accept explicit `--branch`; `main` remains the deliberate compatibility default. `run_ref` and `store_deps` expose branch-specific APIs with default-`main` compatibility wrappers. Branch lookup occurs before runtime-module availability, so a warm VM cannot make a different branch appear bound.

The bounded BEAM evaluator remains a documented design boundary, not an OS sandbox. That is intentional and remains out of scope.

## Source evidence

- `src/gleamunison/cli_lifecycle.gleam` defines `StoreContext(store_path, manifest_path, root_dir)` and derives siblings from one selected store file.
- `src/gleamunison/cli_pkg.gleam` uses the lifecycle resolver rather than a hard-coded `.gleamunison/store.dets` path and retains the selected package branch.
- `src/gleamunison/cli_run.gleam` parses `--branch`, passes it through both text/JSON execution and inspect paths, and documents the default in help.
- `src/gleamunison/run_ref.gleam` resolves a missing store ref through the selected namespace before checking whether a VM module is already loaded. Builtin/jet availability remains explicit.
- `src/gleamunison/store_deps.gleam`, `cli_unpublish.gleam`, and `cli_purge.gleam` use branch-specific dependency, name, closure, and namespace operations.
- `docs/operations/trust-and-key-rotation.md` states the actual one-key production surface and labels overlap tests as library-only.

## Regression evidence

The focused branch regression binds the same name to different definitions on `release` and `main`, runs `release` first, then runs `main` in the same VM. The selected values remain distinct, proving namespace selection is data-driven rather than satisfied by a previously loaded module.

The lifecycle regression proves an explicit store file owns `/published` and its root directory. Relative environment overrides retain the established compatibility error:

```text
GLEAMUNISON_STORE_DIR must be an absolute path, got: relative/store
```

The run help surface now states:

```text
[--json] [--inspect] [--store path] [--branch name]
The branch defaults to main; --branch selects another namespace.
```

## Live exit-code proof

An absent 64-hex reference was run in plain and JSON modes from the rebuilt source:

```text
plain: exit 2
not in the store: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa (publish it or sync it first)

json: exit 2
not in the store: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa (publish it or sync it first)
```

JSON and plain modes therefore retain one unresolved-reference classification. The compiler emitted only the pre-existing unused `None` import warning in `test/sync_accept_test.gleam`.

## Verification record

All timestamps are EAT (UTC+3).

- `gleam format --check src test`: exit 0.
- `gleam check --target erlang`: exit 0; one pre-existing unused test import warning.
- `gleam clean && gleam test`: exit 0; **611 passed, 0 failures**.
- `git diff --check`: exit 0.
- `bb scripts/verify_production_boundaries.clj`: exit 0; **15/15 gates PASS**.
- Integrated gate included format, diff-check, suite, escript build, artifact contract, CLI truth, HTTP boundary, release contract, upgrade/rollback, playbook, CLI errors, dashboard safety, parser, playbook runner, and LOC ceiling.
- Playbook result in the gate: **934 passed, 0 failed, 238 excluded**.
- Every changed production file is below 500 LOC; largest changed production file is `run_ref.gleam` at 472 LOC after formatting.
- The gate generated `docs/verification/production-boundaries-2026-10-24.md`; it is evidence, not a cycle-2 source change.

## Remaining risks and non-goals

- Same-VM BEAM execution is bounded, not hostile-process isolation. The README and production-boundary witness retain that limitation honestly.
- Production trust configuration still supports one signer at a time. Multi-key overlap requires a separately specified operator-facing configuration API.
- The repository still contains the user-owned `gleamunison_escript` artifact and the pre-existing `docs/verification/production-boundaries-2026-10-23.md` edit. Neither is part of the cycle-2 commit.
- The new 2026-10-24 gate witness is generated evidence and should be committed only if the cycle’s atomic documentation commit intentionally includes it.

## Rich Hickey certification

Cycle 2 removed competing answers instead of adding a policy maze: one store context, one explicit branch value, and one honest trust configuration surface. The warm-VM regression matters because it proves the data model wins over incidental process state—the kind of hidden complection Rich Hickey would make us delete before calling the system mature.
