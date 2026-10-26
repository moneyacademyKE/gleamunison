# Utility Scripts

Babashka (`bb`) and shell scripts for gleamunison development, verification and
release.

**Requirements:** [Babashka](https://babashka.org/) (`bb`), Gleam, Erlang/OTP
27–29, and the ordinary shell/zip tooling used by the artifact build. The
dashboard-safety gate also needs Bun. Gates pin their own tool PATH; run them
from the repo root.

```sh
bb scripts/verify_production_boundaries.clj   # the whole battery, in one command
```

## The gate battery

`verify_production_boundaries.clj` runs every release gate in sequence, times
each one, and writes a witness to `docs/verification/production-boundaries-<date>.md`
(gate table + machine-readable JSON + exclusions + unresolved risks). It exits
non-zero if any non-informational gate fails, so it is safe to use as a single
pre-merge check.

| Gate | Command it runs | What it proves |
|---|---|---|
| format | `gleam format --check src test` | formatting is canonical |
| diff-check | `git diff --check` | no whitespace damage |
| suite | `gleam test` | unit tests |
| build-escript | `./build_escript.sh` | the artifact builds |
| artifact-contract | `scripts/test_artifact.sh` | version, datalog engine modules and test modules in the archive |
| cli-truth | `scripts/test_cli_truth.clj` | CLI surface, help, exit codes |
| http-boundary | `scripts/test_http_boundary.sh` | dashboard routes, static assets, clean shutdown |
| release-contract | `scripts/test_release_contract.clj` | two clean builds are byte-identical |
| upgrade-rollback | `scripts/test_upgrade_rollback.clj` | upgrade and rollback paths, corrupt artifact handling |
| playbook-default | `scripts/run_playbook_tests.clj` | end-to-end playbook conformance |
| cli-errors | `scripts/test_cli_errors.clj` | CLI error contract: every bad invocation fails loudly and cleanly |
| dashboard-safety | `scripts/test_dashboard_safety.mjs` | hostile names/expressions stay text, never markup or code |
| parser | `scripts/test_parser.clj` | every playbook file parses |
| playbook-runner | `scripts/test_playbook_runner.clj` | the runner fails closed on crash, nonzero child, timeout, stale exclusion |
| loc-ceiling | `wc -l` over touched files | no agent-written file over 500 LOC |

Individual gates can be run on their own — the table above is the whole list.

## Playbook runner

### `run_playbook_tests.clj`

Parses playbook Markdown from `docs/playbook/`, extracts eligible S-expression
cases, and evaluates them against the real runtime. Selected host-backed levels
use their `levelN` implementation; documented cases use a persistent REPL
session with explicit reset points. Process and per-level timeouts prevent a
hung case from wedging the run. Levels with no executable cases are reported as
`:excluded` only when their pinned policy matches, never as passes.

```sh
bb scripts/run_playbook_tests.clj            # gate mode: fails on regression, skip, or stale exclusion
bb scripts/run_playbook_tests.clj --strict   # completeness report (see below)
```

Default mode is the gate. It fails on a real failure, on a skip, and on an
exclusion whose recorded fingerprint no longer matches the level's cases.

`--strict` is **not** a gate. It uses an empty exclusion policy, so it rejects
every exclusion by design and cannot pass while prose-only levels exist. Run it
when auditing coverage, not as a pass/fail signal — a permanently-red battery
trains people to ignore red.

### `playbook_exclusions.edn`

The exclusion policy: level number → reason plus a SHA-256 fingerprint of that
level's cases. If the playbook text changes, the fingerprint stops matching and
the default-mode gate fails until the entry is re-reviewed. This is what keeps
the exclusion list from silently rotting.

### `playbook_policy.clj`

Reads the exclusion policy, computes fingerprints, and classifies each level's
disposition (`:pass`, `:excluded`, `:stale-exclusion`, `:fail`). `--strict`
selects the empty policy.

### `playbook_session.clj`

Process layer for host-backed levels and REPL sessions: spawn the configured
executable with a timeout, classify the outcome, and detect crashes from stderr
(`escript:`, `internal error`, crash dumps). Shared by the runner and its test.

### `test_playbook_runner.clj`

Tests `playbook_session.clj` against deliberately hostile fake executables — a
crashing one, a hanging one — so the runner's timeout and crash classification
are proven rather than assumed.

## Development loop

| Script | Purpose |
|---|---|
| `watch.sh` | rebuild on source change (`./scripts/watch.sh [--test]`) |
| `watch_scratch.clj` | watch `scratch.lisp` and verify it on save; creates the file if missing (gitignored) |
| `loop_infinite.clj` | infinite dogfooding loop: zombie cleanup, retry detection |
| `dogfood_loop.clj` | update numeric ranges from `dogfood_data.json`, or build and run the level-70 certification probe |

## Generation and docs

| Script | Purpose |
|---|---|
| `generate_docs.sh` | generate the stdlib HTML docs into `docs/stdlib/` |
| `generate_levels.clj` | data-driven dogfood level generation |
| `run_coverage.clj` | BEAM code coverage over `build/dev/erlang/gleamunison/ebin` |

`refactor_dispatch.clj` used to live here. It has been moved to
`scripts/archive/refactor_dispatch.clj`: its template still contains three
commands and calls a function that no longer exists, so running it would
replace the current dispatch with a tree that does not compile.

## Loop and dogfood docs

The `bb dogfood-*` tasks are legacy development utilities, not substitutes for
`gleam test` or the playbook gate. In particular, `dogfood-verify` builds and
runs the level-70 probe; it does not execute every level.

Earlier loop/generator write-ups are retained as historical context rather than
current architecture guidance:

| Doc | Status |
|---|---|
| [`docs/DOGFOOD_LOOP.md`](../docs/DOGFOOD_LOOP.md) | historical loop methodology; check scripts/source before reuse |
| [`docs/ROADMAP_ITEMS.md`](../docs/ROADMAP_ITEMS.md) | completed v2-generator improvement list, not the current roadmap |

Use [`docs/ROADMAP.md`](../docs/ROADMAP.md) for current remaining scope and
[`docs/README.md`](../docs/README.md) for the documentation map.

## `bb` tasks (from `bb.edn`)

| Task | Runs |
|---|---|
| `bb dogfood-loop` | `scripts/loop_infinite.clj` |
| `bb dogfood-register` | `scripts/dogfood_loop.clj --register` |
| `bb dogfood-verify` | `scripts/dogfood_loop.clj --verify` |
| `bb watch-scratch` | `scripts/watch_scratch.clj` |

## `scripts/archive/`

Scripts whose work is done, kept for reference and removed from the live
surface. See `scripts/archive/README.md` — do not run them against the current
playbook.
