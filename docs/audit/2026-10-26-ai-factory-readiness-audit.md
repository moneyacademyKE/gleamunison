# Audit: AI software factory readiness for in-database apps

**Date:** 2026-10-26 (EAT) · **Branch:** `fix/component-audit-2026-10-24` · **Audited HEAD:** `bc8ce0b` · **Task:** `bk-bd24`

## Verdict

**Needs work. The substrate is real; the factory loop is not closed.** A local
content-addressed pipeline can test, attest, publish and run definitions. An agent cannot
yet reliably discover that content, generate it into the store, give it durable application
data, or serve it as an app. More urgently, **the untrusted-execution profile does not gate
MCP evaluation**. Do not expose MCP to untrusted callers on that profile.

This was a source-and-runtime audit, not a vote on the architecture. Production source was
not changed. Probes used temporary stores or a copy of an existing fixture; no push,
publish-to-a-remote, release, deploy, tag or merge occurred.

## Blockers

### Critical — MCP evaluation bypasses the untrusted-execution boundary (`bk-0780`)

`POST /mcp` goes directly to `handle_mcp_route`; it never calls the sandbox admission used
by `/eval` and `/define` (`src/gleamunison_http.erl:416-440`). MCP then evaluates through
`repl_eval.do_eval` (`src/gleamunison/mcp_session.gleam:331-350`). This contradicts the
nearby route invariant: “One admission gate for every route that evaluates caller-supplied
code” (`src/gleamunison_http_routes.erl:31-45`).

Live probe under `GLEAMUNISON_PROFILE=untrusted-execution`:

| Request | Result |
|---|---|
| `GET /eval?expr=(+ 1 2)` | HTTP 403, `missing_external_executor` |
| MCP `tools/call eval` for `(+ 1 2)` | HTTP 200, `3 : Int` |
| MCP `eval` for `file-read` of a controlled marker | HTTP 200, marker contents returned |

The marker contained only `factory-audit-marker`; no private file was read. The authority is
real, not theoretical: `file-read` calls `file:read_file/1` (`src/m_00000035.erl:1-10`), and
`http-get` can make network requests (`src/m_00000034.erl:1-20`). The baseline also installs
Console, State, Remote and LLM handlers (`src/gleamunison_repl_ffi.erl:25-97`). “Read-only”
here means no `define` form; it does **not** mean no effects or no host authority.

**Required before untrusted MCP exposure:** one admission policy covering every code-entry
transport, with a regression that proves MCP cannot evaluate when the profile refuses host
execution. Request authentication and the existing wall-clock timeout are not substitutes
for this boundary.

### High — builtin-dependent definitions acquire an invalid identity (`bk-9e7e`)

Fresh-store reproduction with `keys-of = (lam d (dict-keys d))` and a real passing test:

| Step | Exit | Observed result |
|---|---:|---|
| `test generic.lisp` | 0 | 1 test passed; signed evidence attached to `29642288…` |
| `publish generic.lisp` | 1 | `content_hash_mismatch_or_invalid_definition` |
| `run 29642288…` | 2 | not in the store |

The source chain is complete:

1. `BTerm` carries a name and ref but no type (`src/gleamunison/bootstraps.gleam:14-17`).
2. An uncached `RefTo` infers `TypeVar(-1)` (`src/gleamunison/inference.gleam:106-110`).
3. A term's type participates in its content identity (`src/gleamunison/codebase.gleam:272-281`).
4. The codec rejects negative type variables (`src/gleamunison_definition_codec.erl:94-101`),
   and CAS collapses that decode failure into the observed error (`src/gleamunison_cas.erl:22`).

**Important correction to the earlier feasibility report:** this is not a blanket ban on
polymorphic definitions. A positive control, `(define identity (lam x x))`, passed, published
as `4faed7f1…`, and ran with argument `42`, returning `42`. The defect is the unresolved `-1`
sentinel entering identity, not the existence of ordinary non-negative type variables.

**Required for the factory:** declare honest builtin types and test publication plus execution
for generic accessors, JSON and file/network builtins. Do not “fix” this by teaching the codec
to accept `-1`; that would make an unknown type part of a supposedly precise identity.

### High — MCP returns name hashes where agents expect runnable content refs (`bk-56c2`)

With `shout` explicitly loaded into MCP, `get_definition` returned
`b6efa0bad673…`, exactly SHA256 of the name `shout`. The stored, runnable content hash is
`4544f0246276…`. Running the MCP-provided ref exited 2, not-in-store; running the real content
hash printed `héllo from the store` and returned `0`.

`codebase_index.ref_hex` deliberately uses `repl_eval.ref_for_name(name)`
(`src/gleamunison/codebase_index.gleam:40-58`), and that helper hashes the name
(`src/gleamunison/repl_eval.gleam:141-143`). Yet the MCP session describes its results as
content-addressed refs (`src/gleamunison/mcp_session.gleam:1-4`).

Name refs have a legitimate internal role in dependency loading. The defect is presenting one
as a content identity an agent can feed to `run`. Return distinct, accurately named fields, or
return the actual content ref alongside the name/module ref; add an MCP-to-run roundtrip test.

## Warnings

### Agent sessions do not share the durable codebase (`bk-fe15`)

`mcp_session.boot` loads only genesis definitions (`src/gleamunison/mcp_session.gleam:28-38`).
In a server pointed at a copied store containing published `shout`, MCP could not find it.
In the same server, HTTP `/define factory_probe=42` followed by `/eval factory_probe` returned
`42`, while MCP still reported `definition not found: factory_probe`.

Thus MCP, the HTTP session and the published store are three different views. An agent cannot
assume that what it sees is what `run` executes. Choose an explicit read model over branch
namespace + CAS, and define whether live sessions are overlays on that truth or intentionally
separate scratch workspaces. Do not merge mutable session state into CAS and call it simple.

### The four factory gaps are confirmed, with one correction

| Missing loop stage | Evidence | Classification |
|---|---|---|
| Durable agent write path | Seven MCP tools exist, none publishes (`mcp_session.gleam:173-224`); HTTP define is live-session only (`gleamunison_http_routes.erl:84-114`) | Feature gap |
| Database ability and durable app data | Ordinary verify of `db-assert` fails `E001 undefined variable`; Datalog is loaded by its own CLI (`cli_datalog.gleam:33-47`) | Feature gap |
| Route binding for published content | Fixed HTTP dispatch has no name/hash app route (`gleamunison_http.erl:442-477`) | Feature gap |
| Wired generation loop | `sap`, `patch`, `prompt`, `schema_printer` have test imports only; README explicitly says no runtime wiring (`README.md:229-244`) | Feature gap |

**Correction:** the Datalog engine is not merely pure-functional. It has immutable transactions
(`gleamunison_datalog/src/03_transact.lisp:1-41`) **and** an in-process mutable transactor actor
(`gleamunison_datalog/src/13_actor.lisp:1-64`). What it lacks is durable application persistence
and availability to ordinary published definitions. The definition store's DETS durability does
not automatically become an application database.

### Tests prove the happy path, not the factory boundaries

- MCP HTTP tests prove arithmetic and bearer auth, not sandbox admission or host authority
  (`test/mcp_http_test.gleam:40-85`).
- MCP session tests reject `define`, but do not reject effects (`test/mcp_session_test.gleam:51-66`).
- A test explicitly expects a name hash but never tries it with `run`
  (`test/source_budget_test.gleam:163-172`).
- The builtin publication failure has no end-to-end regression covering test → evidence →
  publish → run.

This is why 694 passing tests and the live defects can both be true. Green suites measure the
contract they exercise, not the contract we wish they exercised.

### Scaling risk — every MCP graph query rebuilds the index (`bk-9a58`)

`callers_of`, `deps_of` and `defs_by_kind` regenerate index source per call
(`src/gleamunison/mcp_session.gleam:235-285`). `eval_index_source` rereads and evaluates the
full engine with the new datoms (`src/gleamunison/codebase_index.gleam:124-157`). No cached
engine or index lives in `SessionState`.

This is an obvious factory-scale hazard, **not a measured latency regression**: no benchmark
was run. Measure realistic codebase sizes before adding a cache or persistent index.

## Nits

- `tools_list_offers_four_tools_test` now covers a seven-tool surface and checks only a subset
  (`test/mcp_session_test.gleam:68-77`). Its name and assertion strength have drifted apart.
- README's suite counts say 649 (`README.md:11`, `README.md:262`); the audited run reports 694.
- The earlier report's phrase “the store only accepts the monomorphic subset” was too broad;
  the positive identity-function control above is the corrective evidence.

## Good calls worth preserving

- The content-addressed admit → store → run chain works for admitted content. The existing
  attested effectful `shout` fixture executed successfully by hash.
- Publication and execution consult the same turnstile rule (`src/gleamunison/turnstile.gleam:53-68`,
  `src/gleamunison/run_ref.gleam:109-139`) instead of maintaining two evidence policies.
- Thirteen Datalog modules are written in Gleamunison itself, and the codebase index already
  uses that engine. A live Datalog assertion returned transaction `1`.
- LLM is an actual baseline ability; SAP, prompts and patches are honestly documented as
  library-only rather than marketed as a finished generator.
- Static traversal, request auth, artifact reproducibility, CLI refusal behavior and the
  production gates all passed. Those are useful foundations, not evidence that MCP is sandboxed.

## Verification receipts

All commands ran sequentially on macOS arm64 with the prescribed tool PATH.

| Gate | Result |
|---|---|
| `gleam test` | **694 passed, no failures** |
| `gleam format --check src test` | exit 0 |
| `gleam check --target erlang` | exit 0; one pre-existing unused-`None` warning |
| `bb scripts/run_playbook_tests.clj` | **934 passed, 0 failed, 238 excluded** |
| CI / verification / release contracts | exit 0; clean builds byte-identical |
| CLI truth / CLI errors | 22 checks passed / 0 failures |
| HTTP boundary / LSP stdio | exit 0 / 0 failures |
| Integrated production gate | **PASS, 15 gates** |

Witness: `docs/verification/production-boundaries-2026-10-26.md` at audited HEAD `bc8ce0b`.
The CI matrix itself was not run locally; that remains an explicit witness exclusion. No
performance benchmark or external-provider LLM call was made.

## Recommended order of work

1. **Close the MCP authority bypass.** One admission owner for all caller-supplied code.
2. **Type the builtins.** Preserve codec strictness; prove publish + run, not just inference.
3. **Make agent identity and state coherent.** Branch namespace + CAS as the durable read
   model; distinguish name refs from content refs; define scratch-session overlays explicitly.
4. **Add one `Db` ability with durable ownership.** Effects and authority belong in the type
   and admission model, not in accidental ambient primitives.
5. **Expose the existing evidence pipeline as the agent write path.** Generation must still
   pass test/attestation/publish; do not add a privileged direct-store backdoor.
6. **Bind admitted names/hashes to routes, then wire generation.** These are assembly once the
   identity, authority and storage contracts are true.

## Rich Hickey recommendation

Do not build the factory by adding four disconnected conveniences. Establish one durable
codebase read model, one authority policy and one honest type for every builtin. Then the
write path, database and routes compose with the store instead of each inventing a second
version of what code exists and what it may do. The tempting shortcuts—accepting `-1`, treating
MCP as “read-only,” or calling a name hash content identity—complect identity with wishful
naming. Reject those; make the existing admission rule true everywhere.
