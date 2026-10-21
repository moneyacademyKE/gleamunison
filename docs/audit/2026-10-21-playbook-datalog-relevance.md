# Playbook and Datalog: Relevance Audit

**Date:** 2026-10-21 16:40 EAT
**Tree:** `main` @ `093d274` (v3.24.0)
**Question:** both subsystems were built while hunting bugs. Are they still relevant?

**Verdict:** both are load-bearing, not scaffolding. Playbook works and should stay
(and join CI). Datalog works in-repo but is **broken as shipped** in three of its four
surfaces.

---

## 1. Playbook

### What it actually is

1172 levels across 40 `docs/playbook/*.md` files. The runner
(`scripts/run_playbook_tests.clj`) parses fenced code blocks, skips docs-only
languages, and executes the remaining forms through a live REPL session.

### Live measurement (this audit, not a claim from a receipt)

```
bb scripts/run_playbook_tests.clj
exit=0
{:passed 928, :failed 0, :skipped 0, :timed-out 0, :excluded 72}
```

- 946 of the first 1000 levels carry executable cases.
- 928 pass, 0 fail, 72 excluded via `scripts/playbook_exclusions.edn`.
- Exclusions are SHA-256 pinned to the source: editing a level invalidates its
  exclusion and fails the run. That design is sound.
- Runtime: ~11 seconds.

This is real end-to-end conformance coverage of the language and runtime, distinct
from the 508 Gleam unit tests. It is worth keeping.

### Gap 1: it is not in CI

`grep -n "playbook" .github/workflows/*.yml` returns nothing. The playbook runs only
inside the local integrated gate (`scripts/verify_production_boundaries.clj`:
`playbook-default`, `playbook-strict`). CI runs `gleam test` and nothing else, so
conformance regressions land on `main` green.

### Gap 2: strict mode has no teeth

Strict mode always exits 1 (72 manual exclusions are policy), and the gate records it
as `informational` in the witness exclusions. A battery that cannot fail is
documentation. Default mode does exit 0 and would fail on a real regression, so
`playbook-default` is the only gate-shaped half.

### Gap 3: levels above 1000 are never run

`selected-levels` defaults to `(range 1 1001)`. Above that ceiling sit 172 levels, of
which 6 carry executable cases (6 cases total). Small, but silently skipped.

### Scaffolding that has outlived its purpose

`scripts/make_placeholders.clj`, `scripts/add_level_placeholders.clj`,
`scripts/refactor_playbooks.clj` are one-shot refactoring tools from the debugging
era. They are referenced only by `scripts/README.md` and an old gap-analysis doc. The
placeholders they wrote were subsequently replaced by real content, which is why 946
levels now execute. Safe to delete, or move to `scripts/archive/`.

---

## 2. Datalog

### What it actually is

A native Datalog engine (ADR-0062) self-hosted in Gleamunison's own language: 13
`.lisp` modules under `gleamunison_datalog/src/` (core, index, transact, schema,
query, aggregate, pull, temporal, rules, graph, vector, bm25, actor), plus 4 `.lisp`
test files. 20 files tracked in git.

### What depends on it

| Surface | Path |
|---|---|
| CLI command | `gleam run -- datalog <file.lisp>` → `cli_datalog.run/1` |
| MCP tool: callers | `mcp_session.callers_of/2` → `codebase_index.eval_index_source/1` |
| MCP tool: deps | `mcp_session.deps_of/2` → same |
| MCP tool: defs-by-kind | `mcp_session.defs_by_kind/2` → same |

`codebase_index.eval_index_source/1` calls `cli_datalog.read_engine/0`, which reads the
13 engine files from **paths relative to the current working directory**.

Test coverage exists and passes: `test/datalog_test.gleam`,
`test/cli_datalog_test.gleam`, `test/codebase_index_test.gleam`,
`test/mcp_graph_test.gleam` (508 suite green).

### Gap 1: the escript cannot load the engine (proven)

```
cd /tmp && gleamunison_escript datalog .../test_core.lisp
ERROR: engine source not found: gleamunison_datalog/src/01_core.lisp
exit=1
```

The escript bundles 262 `.beam` files and **zero `.lisp` files**. Every datalog-backed
surface therefore fails from any directory other than the repo root. It fails closed
(exit 1), which is correct, but the feature is unusable.

### Gap 2: the published Hex package does not contain the engine (proven)

`https://repo.hex.pm/tarballs/gleamunison-3.24.0.tar` → `contents.tar.gz` contains
only `src/`, `priv/`, `include/`, `LICENSE`, `README.md`, `gleam.toml`.
`tar tzf contents.tar.gz | grep -c '\.lisp$'` → **0**.

So for anyone consuming gleamunison 3.24.0 from Hex, the `datalog` CLI and the three
MCP index tools cannot work at all.

### Gap 3: debugging leftover committed at the repo root

`scratch.lisp` is tracked (introduced in `0fee49a`), one line, syntactically invalid:

```
(define my_val 42
```

It is the file `bb watch-scratch` watches. Committed malformed input in the repo root
is a trap for anyone running the playbook or `verify` examples.

---

## 3. Recommendations, in value order

1. **Ship the engine.** Copy the 13 `.lisp` modules into `priv/datalog/` (the one
   directory Hex packages), and make `read_engine/0` try, in order: `priv/datalog/`,
   then `gleamunison_datalog/src/` (repo-root development). One change repairs the
   escript, the Hex package, the CLI, and three MCP tools. Keep a single source of
   truth with a build step or symlink so the two copies cannot drift.
2. **Put `playbook-default` in CI.** It costs ~11 seconds and is the only broad
   end-to-end conformance signal the project has.
3. **Extend the runner ceiling** from `(range 1 1001)` to cover all parsed levels
   (1173). Gains 6 executable levels and removes a silent skip.
4. **Decide strict mode's role.** Either make it a real gate by burning down
   `playbook_exclusions.edn`, or stop listing it as a battery and describe it as a
   report. A permanently-red battery trains people to ignore red.
5. **Delete `scratch.lisp`** and add it to `.gitignore` (the watcher creates it).
6. **Archive the three placeholder scripts** under `scripts/archive/`; their work is
   done and keeping them implies the playbook is still placeholder-generated.

---

## 4. Evidence index

```
bb scripts/run_playbook_tests.clj                    # 928 passed / 0 failed / 72 excluded
bb /tmp/measure_pb.clj                               # 1172 parsed, 946 with cases
grep -n playbook .github/workflows/*.yml             # no matches
unzip -l gleamunison_escript | grep -c '\.lisp$'     # 0
tar tzf /tmp/hexpkg/contents.tar.gz | grep -c '\.lisp$'  # 0
cd /tmp && gleamunison_escript datalog ...           # engine source not found, exit 1
git ls-files scratch.lisp                            # tracked
```
