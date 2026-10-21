# Dead code inventory — 2026-10-21

Follow-up to `2026-10-21-playbook-datalog-relevance.md`. Tree: `main` @ `6cc3dd8`, v3.24.0.
Every claim below is a command output from this run, not an impression.

## Method

| Check | Tool | Result |
|---|---|---|
| Unused imports / vars / private fns / unreachable | `gleam build` from a clean `build/` | 31 warnings in our code (2 more are in vendored `gleamy_structures`) |
| Unused exports | `xref:analyze(exports_not_used)` over `build/dev/erlang/gleamunison/ebin` | 223, of which 23 survive grep verification |
| Unused local functions | `xref:analyze(locals_not_used)` | 0 |
| Module reachability | import/`@`-call scan over `src/` + `test/`, excluding the generated coverage runner | 6 dead modules |
| Doc reachability | filename scan across repo | 27 orphan docs |

Note on method: `xref` alone is not sufficient — it flagged `dogfood_data:load_levels/1`, which is an
`@external` declaration with no beam function, and it cannot see dynamic dispatch
(`gleamunison_jets:fib/1` is called from a generated `fun` string). Each of the 23 survivors was
verified by hand: exactly one textual occurrence in `src/` + `test/`, the definition itself.

## A. Six dead modules — 285 lines

| Module | Lines | Why it is dead |
|---|---|---|
| `src/gleamunison/filepath.gleam` | 98 | Superseded by the `filepath` Hex package (already a dependency). No import anywhere. |
| `src/gleamunison/config.gleam` | 68 | Env/TOML/CLI precedence loader. No caller in `src/` or `test/`. |
| `src/gleamunison_property.gleam` (`.erl`) | 49 | Property-testing helpers (`check/2`, generators). No test uses them. |
| `src/gleamunison/template.gleam` | 34 | Curly-var renderer. No caller. |
| `src/gleamunison_adapters.erl` | 28 | `adapt/2`, `find/2`, `register/3` — no caller. |
| `src/gleamunison/metrics.gleam` | 8 | Thin wrapper over `gleamunison_metrics.erl`; the Erlang module is the real one. |

The only references to the four Gleam modules are in `scripts/generate_docs.sh`, which documents
them as `NEW` API. That script is a doc generator, not a consumer.

## B. Sixteen dead public functions in live modules

| Function | Where | Note |
|---|---|---|
| `log.debug_context/2`, `info_context/2`, `warn_context/2`, `error_context/2` | `log.gleam:59-71` | All four context loggers unused; plain `log.info` etc. are used. |
| `genesis.builtin_state_get/0`, `builtin_state_put/0` | `genesis.gleam:11,15` | Defined, **never registered** in `bootstraps.gleam` (54 of 58 builtins are). |
| `genesis.builtin_ability_llm/0`, `builtin_ability_llm_stream/0` | `genesis.gleam:227,232` | Same: defined, never registered. The LLM ability is not in the bootstrap env. |
| `capability.run_scoped/3` | `capability.gleam:90` | CHANGELOG v3.24.0 calls this the sandbox guarantee. Nothing calls it. |
| `sync.push_sync/4` | `sync.gleam:196` | Push protocol implemented; only `pull_sync` is wired (`cli_sync`, `cli_pkg`). |
| `evidence.allow_unsigned/0` | `evidence.gleam:57` | The unsigned-bypass helper. Good that nothing calls it. |
| `health.run_all/0` | `health.gleam:36` | `readiness/0` and `run_checks/1` are the used entry points. |
| `mcp_session.session_defs/1` | `mcp_session.gleam:101` | Superseded by the internal state accessors. |
| `identity.local_var_index/1` | `identity.gleam:66` | Accessor never called. |
| `llm_budget.refusal_retryable/1` | `llm_budget.gleam:176` | Retry classification exists but no caller. |
| `datetime.to_iso8601/1` | `datetime.gleam:57` | `now_iso8601` is the used one. |

Two of these are not cleanup decisions but **wiring questions**:

1. `genesis.builtin_ability_llm` / `_stream` / `builtin_state_get` / `builtin_state_put` are four of
   the 58 genesis builtins, and the only four never placed in the bootstrap table. Either the LLM and
   state abilities are supposed to be reachable from programs (then this is a missing registration,
   not dead code) or the definitions should go.
2. `capability.run_scoped` is the API the v3.24.0 changelog advertises as making untrusted execution
   "boring". Nothing calls it. The claim and the code disagree.

## C. Generated file committed to `src/`

`src/gleamunison_coverage_runner.erl` (58 lines) is **generated** by `scripts/run_coverage.clj`
(line 98) and **deleted** by the same script afterwards (line 119). It is tracked in git anyway, so a
run that is interrupted leaves it behind and `gleam build` compiles it into the app. It should be
gitignored, not tracked.

## D. Dead fixture

`test/fixtures/datalog_probe.lisp` — no test, script, or shell command references it. The only
mention is its own header comment. It was added during the datalog work and never consumed.

## E. 31 compiler warnings in our code

| Kind | Count | Files |
|---|---|---|
| Unused imported item | 15 | `mcp_session` (6), `llm` (3), `repl` (2), `lsp_types` (2), `cli_publish`, `codebase_index_test`, `storage_recovery_test` |
| Unused imported type | 5 | `llm` (2), `mcp_session`, `llm_middleware`, `lsp_features` |
| Unused imported module | 4 | `lsp` (2), `codebase_index`, `codebase_index_test` |
| Unused variable | 3 | `trust.gleam:52,53`, `mcp.gleam:158` |
| Unused private function | 1 | `mcp_session.gleam:463` |
| Unused private constructor | 1 | `cancellation.gleam:5` |
| Unused imported value | 1 | `mcp_session.gleam:21` |
| Unreachable code | 1 | `test/datalog_engine_priv_test.gleam:47` |

`mcp_session.gleam` alone accounts for 8 of the 33 warning locations — it looks like a module that
was rewritten and had imports added ahead of use.

## F. 101 over-exports (not dead — `pub` where `fn` would do)

`xref` finds no external caller for 101 exported functions that are still used *inside* their own
module. Not dead code; a visibility-tightening pass. Largest clusters: `auth` (`scope_at_least`,
`scope_name`, `identity_scopes`, `is_loopback`), `filepath`, `http_client`, `inference`.

## G. Four probes that work but never run

Verified live this run — all four exit 0:

| Probe | Result |
|---|---|
| `bb scripts/test_cli_errors.clj` | CLI error contract: 0 failures |
| `bun scripts/test_dashboard_safety.mjs` | hostile names/expressions stay text: PASS |
| `bb scripts/test_parser.clj` | parses every `docs/playbook` file |
| `bb scripts/test_playbook_runner.clj` | fail-closed on injected crash, nonzero child, timeout, stale exclusions |

None is invoked by `verify_production_boundaries.clj` or CI. They are real coverage that rots
unwatched — either wire them into the gate or accept they are manual.

## H. Stale documentation claims

`docs/ARCHITECTURE.md:107`, `docs/PLAYBOOK.md:127`, `docs/ROADMAP.md:5`, and
`docs/gap-analysis-gleamunison-vs-baml.md:30` all still claim **5,696** conformance levels. The
measured number after the v3.24.0 work is 1,172 defined / 934 executable. The README was corrected;
these four were not.

`docs/gap-analysis-low-complexity.md:38` still instructs the reader to edit
`make_placeholders.clj`, which now lives in `scripts/archive/`.

27 docs have no inbound reference at all. Most are historical (walkthroughs, round-2 learnings, gap
analyses against other projects) and should probably move to `docs/archive/` rather than be deleted.

## Recommended order

1. Delete the six dead modules and the dead fixture (285 + 3 lines, zero callers, zero behaviour change).
2. Clear the 31 warnings (pure deletions; `gleam build` proves it).
3. `git rm --cached src/gleamunison_coverage_runner.erl` + gitignore it.
4. Decide the two wiring questions (genesis builtins, `capability.run_scoped`) — this is a product
   decision, not a cleanup one.
5. Wire the four probes into the gate, or move them to `scripts/manual/`.
6. Fix the four stale level counts; move orphan docs to `docs/archive/`.

Steps 1-3 and 6 are mechanical and safe. Step 4 needs an answer about intent. Step 5 is a choice
between coverage and honesty.

---

## Resolution — same day, bead `bk-8a6f`

All six recommended steps are done. Commits: `bcc2a24`, `1e7a482`, `851e178`, `0663fac`, `6b26bc4`,
`84b3c19`, `a14034a`, `f543010`. Gate: `bb scripts/verify_production_boundaries.clj` exits 0 with 14
gates passing (witness `docs/verification/production-boundaries-2026-10-21.md`).

| Step | Outcome |
|---|---|
| 1. Six dead modules | Deleted, with their Erlang twins (`gleamunison_property.erl`, `gleamunison_adapters.erl`, `gleamunison_template.erl`). `gleamunison_config.erl` and `gleamunison_metrics.erl` were **kept**: only their Gleam wrappers were dead, the Erlang modules have real `@external` callers. |
| 2. 31 warnings | Zero warnings remain in our code. Two Gleam warnings persist in the vendored `gleamy_structures` package, which is not ours to edit. |
| 3. Coverage runner | Untracked, gitignored, stale copy removed from `src/`. |
| 4. Wiring questions | **Both answered by deleting, not wiring** — see below. |
| 5. Four probes | Wired into the gate (about 6s total), not moved to `scripts/manual/`. |
| 6. Docs | Counts corrected to 1172 defined / 934 executable / 238 excluded, measured this run. 25 orphans found; 22 archived, 3 kept and linked. |

### The two wiring questions, resolved

**Genesis builtins (refs 3, 4, 54, 55).** Not a missing registration. Abilities resolve by *name hash*
(`llm.ability_ref()` returns `Ref(hash_bytes("LLM"))`, and `bootstraps.gleam` registers the ability
*names* directly), so the ordinal accessors were the abandoned design, not a gap. Ref 54 also had a
permanent claim on a hash that nothing could ever resolve. Deleted; the comment in `genesis.gleam`
records that 54/55 stay reserved.

**`capability.run_scoped`.** Deleted, along with its `handle_any` helper and its `to_dynamic` external.
The enforced primitives are `guard_frames` and `check`, both used by tests. What remains open — and is
now recorded in the CHANGELOG instead of implied by a function name — is that **`sandbox_policy` has no
production caller at all**. The `UntrustedExecution` profile is implemented and tested but nothing
executes user code through it: `gleamunison_repl_ffi.erl` calls `gleamunison_eval_scope:run/2`
directly, without frames. That is a real gap between the v3.24.0 claims and the runtime, and it needs a
decision about where the boundary is enforced, not more dead code removed.

### Found while doing the work

`cancellation.Token` was an opaque type whose constructor was never used, because the FFI returned the
atomics reference as an untyped value — the reference never actually entered the type. The Erlang HTTP
client then reached *past* the token into `gleamunison_cancellation:cancelled/1`. The type now holds the
reference, the reference stays inside the module, and the client calls the token's owner
(`cancellation.is_cancelled/1`). Same warning count, one fewer lie in the type.

### Not done, deliberately

Section F (101 over-exports) was not part of the six steps and is untouched: `pub` → `fn` tightening
touches 101 call sites' worth of surface area and deserves its own pass with its own proof.
