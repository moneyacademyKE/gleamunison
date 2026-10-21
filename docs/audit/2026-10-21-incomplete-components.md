# Incomplete & broken components — 2026-10-21

Scope: `main` @ `b2c369f` (v3.24.0). Everything below was verified with a command
whose output is quoted; nothing here is inferred from memory or from docs.

## Method

1. `gleam build` + Erlang `xref` for dead code (done in the previous pass; not repeated).
2. Marker sweep for `TODO/FIXME/stub/unimplemented/not implemented/no-op` in `src`, `test`, `scripts`.
3. `@external` resolution: all 154 Erlang externals parsed and matched against the
   `-export` lists of all 97 `.erl` modules.
4. Reference graph: every Gleam module checked for a production caller in **both**
   `.gleam` imports and Erlang `gleamunison@module:` calls, and separately for test-only callers.
5. Live probes against the built escript from `/tmp` (no repo on the path) and from the repo root.
6. Doc claims resolved against the tree (module names, script paths, function names).

## What is clean (checked, no defect found)

- **154/154 Erlang externals resolve.** The only non-`src` targets are BIFs (`erlang:`,
  `math:`, `timer:`) and the generated `gleamunison@repl`. No `undef` waiting for a caller.
- **Sync v2 HMAC handshake is real and wired**: `gleamunison_tcp_sync` implements
  hello → challenge → HMAC proof, per-connection nonce, replay table; `ffi_io:tcp_call/2` uses it.
- **LSP** handles initialize/initialized/shutdown/exit/didOpen/didChange/hover/definition/completion
  with real inference-backed hover; **MCP** implements initialize/tools/list/tools/call/ping.
- All 14 gate battery scripts referenced by `verify_production_boundaries.clj` exist.

---

## A. Broken at runtime (proven live)

### A1. `/api/ready` and `/api/health` can never return 200

`gleamunison_readiness:report/0` marks `storage` as **required**, and `storage_check/0`
reads `persistent_term:get({gleamunison, active_storage}, undefined)`. That term is written
only by `gleamunison_storage:new/dets_new/...`, which **no production code calls** — the only
writers in the tree are `gleamunison_ffi_test.erl` and `gleamunison_health_test.erl`.

Live, escript from `/tmp`, plain `server` start:

```
GET /api/health -> 503
"checks":[{"name":"storage","ok":false,"detail":"storage_unavailable",...}]
"ready":false
```

`docs/OPERATIONS.md:62` documents `/api/ready` as the orchestrator probe. A k8s readiness
probe pointed at it never passes, so the pod never receives traffic.

Two honest fixes, pick one: initialise storage during `server` boot, or stop marking
`storage` required. Right now the probe asserts a resource the runtime never acquires.

### A2. Dashboard assets 404 from the shipped escript

`build_escript.sh:130` packs only `./*.beam ./gleamunison.app ./priv/datalog/*.lisp`.
`priv/static/{css,js}` is not included. `gleamunison_static:resolve/1` additionally roots at
`filename:absname(<<"priv/static">>)`, i.e. **relative to cwd**.

Live, escript from `/tmp`:

```
/api/health                       -> 503
/static/css/dashboard.css         -> 404
/browse                           -> 200   (shell loads, assets do not)
```

Same class of bug as the datalog engine fixed in `bk-389b`: code ships, data does not.

### A3. Every level silently degrades to a stub when the data file is missing

`dogfood_meta.real_levels_list/0` loads `src/dogfood_data.json` by **relative path** and
returns `[]` on error:

```gleam
case dogfood_data.load_levels("src/dogfood_data.json") {
  Ok(levels) -> ...
  Error(_) -> []
}
```

`dogfood.all_levels/0` then fills every missing key with `generic_computation`, which prints
`stub: hash|parse|eval|insert|infer`. Live, escript from `/tmp`:

```
$ ./gleamunison_escript level5000
stub: parse
EXIT=0

$ ./gleamunison_escript level70
--- Level 70: Meta-test runner ---
Failed to load levels: File error: enoent
EXIT=0
```

From the repo root the same commands run real work (`Level 5000: OK`, `Loaded 5696 levels`).
So the shipped escript's `levelN` command is a **no-op that exits 0**. A CI job or user
running the published artifact gets a green result for a suite that executed nothing.

`level70` at least prints the failure; it still exits 0. Silent success is the defect,
not the missing file.

### A4. `gleamunison all` claims completion for levels it never ran

`run_all_levels/1` iterates 1..6696, prints each stub's notice, then prints
`=== All available levels complete ===`. In the degraded state of A3 that sentence is
false for 5,675 of 5,696 levels.

### A5. The metrics subsystem records nothing

`gleamunison_metrics:counter/2`, `gauge/2`, `histogram/2` have **no production callers**
(only `list_metrics/0` is read, by `gleamunison_observability`). `gleamunison_metrics_sup`
is started only from `gleamunison_metrics` itself and from tests.

Live `/api/observability`:

```json
"logs":{"count":0,"limit":1024,"recent":[]},
"metrics":{"counters":{},"gauges":{},"histograms":{}}
```

The endpoint works; the instrumentation behind it does not exist.

---

## B. Half-shipped: implemented, tested, unreachable (1,151 lines)

Modules with **zero production references** (no `.gleam` import, no `gleamunison@mod:` call),
but with tests importing them:

| Module | Lines | What it is |
|---|---:|---|
| `gleamunison/sap` | 382 | Schema-aligned parsing of near-miss model output (fences, trailing commas, Python literals) |
| `gleamunison/sandbox_policy` | 206 | Untrusted-execution profile admission against resource budgets |
| `gleamunison/patch` | 188 | Named content-addressed update propagation |
| `gleamunison/prompt` | 117 | Content-addressed prompts as definitions |
| `gleamunison/trust` | 115 | Key states (active/revoked/expired) and rotation |
| `gleamunison/schema_printer` | 72 | Type → compact prompt schema |
| `gleamunison/health` | 71 | Gleam readiness wrapper; production readiness is the Erlang module |

These are not dead code in the compiler sense — they compile, they are tested, they are
documented as shipped. Nothing can reach them. `sap`/`prompt`/`patch`/`schema_printer` are
the "gap analysis concepts B/C/D" from `docs/gap-analysis-gleamunison-vs-baml.md`; the
concept was built, the wire was not.

`trust` is the sharpest case: `CHANGELOG.md:31` (v3.24.0) says it "owns key states
(active/revoked/expired) and rotation", and `README.md:220` lists it under **Policy & trust**.
There is no enforcement point anywhere in the runtime.

---

## C. Two auth models; production uses the weaker one

- `gleamunison/auth.gleam`: four scopes (`Public`/`DataRead`/`DataWrite`/`Admin`),
  `identity_scopes`, `authorize`, `bearer_identity`, plus `bind_decision`.
- `gleamunison_http.erl:284`: `authorized/2` — one env token, `protected_path/1` returns a
  boolean. **No scopes, no identity, no per-route authority.**

`bind_decision` *is* called (`gleamunison@auth:bind_decision/1`), so the bind gate is wired.
The scope model is not: any holder of `GLEAMUNISON_HTTP_TOKEN` reaches every protected route,
including the `/api/*` routes `auth.gleam` classifies as `Admin`.

That is a policy/implementation split — the documented boundary and the enforced boundary
are different code. `auth.gleam`'s `required_scope/1` is reachable only from tests.

---

## D. Destructive stale tooling (highest immediate risk)

`scripts/refactor_dispatch.clj` is documented in `scripts/README.md:104` as
"regenerate the `gleamunison.gleam` dispatch and split dogfood modules" — presented as routine.

It does this:

```clojure
(spit (str src "/gleamunison.gleam") gleamunison-content-fixed)
(spit (str src "/dogfood.gleam") dogfood-header)
```

Its template contains **three** commands (`server`, `demo`, `repl`) and calls
`repl.start_repl()` — a function that no longer exists (the live API is
`start_repl_loading/1`). The current dispatch has 19 commands.

Running it as documented overwrites the entry module and `dogfood.gleam` with content that
**does not compile**, destroying 16 commands and the dogfood router. The README gives no
warning. Either delete it, archive it, or gate it behind an explicit `--force`.

---

## E. Doc drift created by the dead-code pass

The 2026-10-21 dead-code removal deleted six modules and sixteen functions; the docs were
not updated. Verified by resolving every claimed module name against `src/`:

| Doc | Claim | Reality |
|---|---|---|
| `docs/ARCHITECTURE.md` | `gleamunison/metrics`, `/config`, `/filepath`, `/template` | all four deleted |
| `docs/GLOSSARY.md` | `gleamunison/metrics`, `/template` | deleted |
| `docs/ROADMAP.md` | 8.4 filepath, 8.6 template, 10.2 metrics, 10.4 config, 10.5 health `run_all/0` — all "✓ DONE (v1.1.0)" | modules/functions gone |
| `docs/ROADMAP.md` | 9.4 property-based testing, "`gleamunison_property.erl`" | file does not exist |
| `docs/ROADMAP.md` | 10.1 log "with context dict" | `log.gleam` feeds `dict.new()` at all four call sites — context is structurally always empty |
| `docs/stdlib/index.html` | filepath, template modules | deleted |

Missing scripts referenced by docs:

- `docs/ARCHITECTURE.md` → `scripts/demo.clj`, `scripts/test_runner.clj` — neither exists.
- `docs/DOGFOOD_LOOP.md` → `scripts/next_batch.sh` — does not exist.

Also stale: `docs/gap-analysis-*.md` reference `gleamunison/config`, which is gone.

---

## F. CI enforces 7 of the 14 gate batteries

`verify_production_boundaries.clj` runs 14. CI (`.github/workflows/test.yml`) runs
format, suite, build-escript, artifact-contract, playbook-default, release-contract,
upgrade-rollback. Never run in CI:

`cli-truth`, `http-boundary`, `cli-errors`, `dashboard-safety`, `parser`, `playbook-runner`.

Note `dashboard-safety` shells out to `bun`, which CI never installs — wiring it naively
would fail on the runner. The four orphan probes added in `bk-8a6f` run only on a
developer's machine.

---

## G. CLI surface

### G1. Help advertises 8 of 19 commands

`print_help/0` lists: server, repl, verify, llm, mcp, all, schema-version, levelN.
Dispatch also handles: datalog, find, fmt, replay, tape-to-test, test, publish, evidence,
lsp, sync, pkg, watch, version, help. Fourteen commands are undiscoverable from `--help`.
`demo` exists only to print help.

### G2. Every invocation builds a 6,696-entry dict before dispatch

`pub fn run(args)` opens with `let levels = dogfood.all_levels()`, before the `case args`.
So `--help`, `version`, `datalog`, `mcp` — every command — pays for building 6,696 tuples,
a `list.contains` scan over the real keys per candidate, and `dict.from_list` of the whole set.

Measured on the escript:

```
$ for i in 1..5; do time ./gleamunison_escript version; done
real 0.15 / 0.15 / 0.15 / 0.16 / 0.15
```

150 ms per invocation for a version string. Dispatch is also a linear `case`, so the cost
is paid even when no level is ever touched. `levels` is only consumed by `dispatch`'s
`all` and `levelN` branches.

---

## Summary

| # | Finding | Class | Severity |
|---|---|---|---|
| A1 | Readiness probe permanently 503 (storage never initialised) | broken | high |
| A2 | Dashboard assets 404 from escript (not packaged + cwd-relative) | broken | high |
| A3 | Levels silently degrade to stubs, exit 0 | broken | high |
| A4 | `all` claims completion for levels it skipped | false claim | medium |
| A5 | Metrics subsystem records nothing | broken | medium |
| B | 7 modules / 1,151 lines unreachable (incl. `trust`, `sandbox_policy`) | half-shipped | high |
| C | Scope auth model not enforced; flat token in production | security divergence | high |
| D | `refactor_dispatch.clj` destroys the CLI and breaks the build | destructive | critical |
| E | ARCHITECTURE/GLOSSARY/ROADMAP/stdlib document deleted code | doc drift | medium |
| F | 6 of 14 gate batteries never run in CI | coverage gap | medium |
| G1 | Help lists 8 of 19 commands | discoverability | low |
| G2 | 150 ms + 6,696-entry dict on every CLI call | performance | low |

Suggested order: **D** (one command away from a broken tree), **C** (security boundary),
**A1** (probe that lies), **A3/A2** (silent success), **B** (decide wire-or-delete per
module — that is a product decision, not cleanup), **E/F/G**.

## Resolution (2026-10-21, bead `bk-f912`)

Every finding above is fixed on `main`, one commit per finding. Each claim below
was re-probed after the change; the commands are in the commit messages.

| # | Status | What changed | Commit |
|---|---|---|---|
| D | Fixed | `refactor_dispatch.clj` archived with a note saying why it is unrunnable | `b634db0` |
| G1 | Fixed | `--help` lists all 22 commands, grouped | `28c4244` |
| G2 | Fixed | Level table built only in the level branches; `version` 150 ms → 100 ms | `28c4244` |
| A3/A4 | Fixed | Level data ships in the escript (`priv/dogfood/`), resolves archive → priv → repo; missing data is a non-zero exit; the 6,696 synthetic stubs are gone | `6b34894` |
| A1 | Fixed | `start_server/1` opens storage at boot; `/api/ready` and `/api/health` return 200 on a healthy server | `73a0ef5` |
| A2 | Fixed | `priv/static` ships in the archive; `gleamunison_static:read/1` falls through to it; traversal still 403 | `ddac6bd` |
| C | Fixed | Scopes enforced: admin/write/read tokens, decision in `gleamunison@auth:authorize_scopes/2`, `protected_path/1` deleted | `cc61758` |
| A5 | Fixed | `http_requests_total`, duration histogram, `http_errors_total` and log entries at the response boundary; log table owned by the server process; `/api/logs` JSON repaired | `26fbbd0` |
| B | Decided per module | `health`/`log` wrappers deleted (Erlang owner exists); `sandbox_policy` wired into `/eval` and `/define`; `trust`/`sap`/`patch`/`prompt`/`schema_printer` documented as library-only API | `dc04dbc` |
| E | Fixed | ARCHITECTURE, GLOSSARY, ROADMAP, MANUAL, stdlib index and BAML gap analysis point at the real owners or say REMOVED; generator fixed so it cannot reintroduce the stale blocks | `e127f0a` |
| F | Fixed | `gate-batteries` CI job runs all six uncovered batteries plus `diff-check`, with bun installed | `3defbbd` |

Verification after the fixes:

- `gleam format --check src test` — exit 0
- `gleam test` — 513 passed, 0 failures
- `bb scripts/run_playbook_tests.clj` — 934 passed, 0 failed, 238 excluded
- `bb scripts/verify_production_boundaries.clj` — 15/15 PASS, witness refreshed
- escript from `/tmp`: `/api/ready` 200 (`"ready":true`), `/static/css/dashboard.css` 200,
  `level5000` → `Level 5000: OK`, `level70` → `Loaded 5696 levels.`
- `GLEAMUNISON_PROFILE=untrusted-execution` → `/eval` and `/define` 403 `missing_external_executor`

Two findings were not defects and are unchanged: the 154 Erlang externals all
resolve, and sync v2 HMAC plus LSP/MCP are genuinely implemented and wired.

One caveat worth stating: the readiness fixture called the deleted
`gleamunison@health` wrapper and passed once on a stale beam before failing from
a clean build (`71f5b2a`). A green test run is not proof that the module it calls
still exists.

