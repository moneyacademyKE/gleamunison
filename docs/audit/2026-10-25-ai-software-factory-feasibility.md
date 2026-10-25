# Feasibility: gleamunison as an AI software factory for in-database apps

**Date:** 2026-10-25 (EAT) · **Branch:** `fix/component-audit-2026-10-24` · **Basis:** source reads + live probes in an isolated store (`/tmp/factory-probe`). No production code changed.

## Verdict

**Possible, and closer than the README implies — but not today.** The content-addressed
substrate, the evidence turnstile, a real Datalog engine written in the language, and an
LLM ability all exist. What is missing is a *write path from the agent surface*, a
*database ability with persistence*, a *route binding for published content*, and a
*typed standard library* — and that last one is currently a live defect, not just a gap.

## What already exists (verified)

| Piece | Evidence |
|---|---|
| Content-addressed identity, store, evidence turnstile, `run <hash>` | `id` and `inc` published and executed in an isolated store |
| Datalog engine **written in the language** | 13 modules under `gleamunison_datalog/src/`: core, index, transact, schema, query, aggregate, pull, temporal, rules, graph, vector, bm25, actor — immutable, Datomic-shaped |
| The codebase is itself a Datalog database | `codebase_index.gleam` builds datoms; MCP `callers_of` / `deps_of` / `defs_by_kind` answer from it |
| LLM as a first-class ability | `m_a12979b5` in `baseline_abilities/0` — reachable from the REPL **and** from `run` |
| Agent surface | MCP (7 tools), LSP, HTTP API (`/eval`, `/define`, `/api/*`) |
| Verification | content-addressed evidence, trust policy, execution budgets |

The in-database half is the strong half. A factory that emits schema, rules and queries
in one language, typechecked by one checker and admitted by one hash, is a real design.

## What is missing (each verified)

1. **No write path from the agent surface.** Every MCP tool is read-only
   (`list_definitions`, `get_definition`, `search_definitions`, `eval`, `callers_of`,
   `deps_of`, `defs_by_kind`). `/define` binds in the live web session only. Landing code
   still requires the CLI `test` → `publish` pair. An agent can inspect and evaluate;
   it cannot commit.
2. **No database ability, no persistence.** The ambient namespace has no file-write and no
   DB open/transact; `State` is the process dictionary. The Datalog engine is loaded
   per-process by `cli_datalog` and is **not** in the ambient namespace — a stored
   definition cannot even reference `db-assert` (probe: `E001 undefined variable`).
3. **No route binding.** HTTP routes are a fixed Erlang case table. A published definition
   cannot be served at a URL, so a generated app has no deployment surface.
4. **The generation loop is unwired.** `sap`, `schema_printer`, `prompt` and `patch` are
   implemented, tested and called by nothing (README states this explicitly).

## Live defect found while probing

**Definitions whose inferred type contains the "unknown" sentinel cannot be published.**

| Definition | Inferred type | Publish |
|---|---|---|
| `(lam x x)` | `Fn([0]) -> 0` | ok |
| `(lam x (+ x 1))` | `Fn([0]) -> Int` | ok |
| `(lam d (dict-keys d))` | `Fn([0]) -> -1` | **refused** |
| `(lam s (json-parse s))` | `Fn([0]) -> -1` | **refused** |
| `(lam p (file-read p))` | `Fn([0]) -> -1` | **refused** |

Chain: `bootstraps.gleam` declares builtins with **no type** (`BTerm` carries name + ref
only) → `inference.gleam` returns `TypeVar(-1)` for a `RefTo` with no cached type → the
type is part of the identity hash → `gleamunison_definition_codec:valid/2` requires
`nonnegative(N)` → `decode` fails → `gleamunison_cas` reports
`content_hash_mismatch_or_invalid_definition`, naming neither the sentinel nor the builtin.

Consequence: the store only accepts the monomorphic subset. Generic accessors over dicts,
JSON parsing and file reading are unpublishable, so `run` can never execute them. An AI
factory emits exactly this class of code.

Separately: `http-get` and `file-read` are ambient, ungated primitives
(`src/m_00000034.erl`, `src/m_00000035.erl`) that execute with **no ability handler**.
"Effects as authority" does not cover network egress or arbitrary file read. They run in
the REPL and through `/eval` today; they are only kept out of published content by the
defect above, which is an accident rather than a policy.

## Cheapest credible path

1. **Type the builtins.** Give `BTerm` a declared type so `RefTo` never yields `-1`.
   This is the load-bearing step: without it the identity hash contains "unknown" and a
   whole class of definitions cannot exist in the store.
2. **One `Db` ability.** Handler owns the store: `open` / `transact` / `query`. DETS first,
   Postgres later. Authority stays in one place, and in-database apps get a home.
3. **Route binding.** Namespace name → hash → served at `/app/<name>`, reusing the single
   baseline handler table that `run` already folds in.
4. **Wire the loop.** `schema_printer` → `prompt` → `LLM` → `sap` → `test` → `publish`,
   with the evidence turnstile as the only admission door.

Steps 3 and 4 are assembly of parts that already exist. Steps 1 and 2 are the work.

## Honest limits

- No OS sandbox, no TLS, single node. A factory running generated code inherits all three.
- The Datalog engine is pure-functional and in-memory: durable application data has no home.
- The type system is HM with algebraic effects, and its own standard library is untyped.

## Rich Hickey note

The defect and the gap are one fact: *the identity of a definition includes its type, and
the type of a definition that calls an untyped builtin is "unknown"*. Adding a `--force`
flag, or making the codec tolerate `-1`, would let the store hold content whose identity
is a sentinel — a second policy answering for the first. Type the builtins instead: one
owner for "what this term means", and the factory's admission rule becomes true rather
than permissive.
