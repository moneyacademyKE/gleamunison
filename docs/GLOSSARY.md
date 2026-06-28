# Glossary

Terms specific to the gleamunison project.

## A

**ADR** — Architecture Decision Record. A document in `docs/adr/` that records a significant design decision, its context, and consequences. 38 records as of v0.8.0.

**Algebraic Effects** — A mechanism for side effects where operations are declared as abilities and handled by dynamically scoped handler functions. Implemented via process dictionary stack in `gleamunison_effets.erl`.

**AST** — Abstract Syntax Tree. The internal representation of code after parsing. Defined in `src/gleamunison/ast.gleam` with 12 term constructors.

## B

**BEAM** — Bogdan's/Björn's Erlang Abstract Machine. The Erlang virtual machine. gleamunison targets BEAM bytecode.

**Build Escript** — The process of packaging all BEAM bytecode into a standalone executable. Run via `./build_escript.sh`. See `docs/BUILD_ESCRIPT.md`.

## C

**Content-Addressing** — The core architectural principle: identity = SHA256 hash of serialized form. A definition's hash IS its identity. Two identical definitions always have the same hash.

**Codebase** — The content-addressed Merkle store where definitions live. Implemented in `src/gleamunison/codebase.gleam`. Append-only: once inserted, definitions never change.

## D

**de Bruijn Index** — A positional variable reference where names are replaced by the distance from the binding site. Used for alpha-equivalence and stable hashing.

**De-Complection** — The central design discipline (Rich Hickey): if two concerns can be separated, they must be separated. Every type and function signature is a binding contract.

**DefinitionRef** — A content-addressed reference to a definition. Contains a SHA256 `Hash`. Defined in `src/gleamunison/identity.gleam`.

**DETS** — Disk Erlang Term Storage. Erlang's native disk persistence engine. Used for durable codebase storage.

**Dogfood Level** — A single conformance test case in the playbook. Each level exercises a specific runtime capability (parse, elaborate, typecheck, compile, load, eval). 1000 levels total.

**Dogfooding** — The practice of using the gleamunison runtime to test itself. The runtime compiles and evaluates its own test expressions.

## E

**Elaboration** — The phase that transforms surface syntax into core terms: resolves names to DefinitionRefs, assigns de Bruijn indices, maps abilities to types. Orchestrated by `src/gleamunison/elaborate.gleam`.

**Erlang FFI** — Foreign Function Interface to Erlang. `.erl` files in `src/` that expose Erlang runtime capabilities to Gleam code. Named `gleamunison_*.erl`.

**Escript** — Erlang's standalone executable format. A shebang line + zip archive of BEAM files. The built escript is `gleamunison_escript`.

**ETS** — Erlang Term Storage. In-memory key-value store with process ownership. Used for volatile codebase storage and global counters.

## G

**Genesis Block** — The set of pre-computed builtin definitions seeded into every codebase. Each builtin has a SHA256 hash and a corresponding BEAM module.

**Genesis Module** — A raw Erlang module (`src/m_*.erl`) implementing a builtin primitive. 52 modules as of v0.8.0. See `docs/genesis-modules.md`.

## H

**Hindley-Milner** — The type inference algorithm used for polymorphic types. Implemented in `src/gleamunison/inference.gleam`.

## L

**LOC** — Lines of Code. The project enforces a strict <250 LOC limit per file. Modules approaching this limit must be decomposed.

**Lowering** — The phase that transforms elaborated types into core type references with unique de Bruijn indices. Implemented in `src/gleamunison/lower.gleam`.

**LRU** — Least Recently Used. The cache eviction strategy used for BEAM module lifecycle management.

## M

**Mnesia** — Erlang's distributed DBMS. Used as a storage adapter for multi-node replicated codebase storage (Phase 5).

**Module Purging** — The process of unloading old BEAM module versions from the Erlang code server (`code:delete/1` + `code:purge/1`) to allow redefinition without collision.

## O

**OTP 29** — Open Telecom Platform version 29. gleamunison targets OTP 29+ for specific API compatibility (`compile:file/2` return format, removed `erlang:type/1`).

## P

**Playbook** — The development methodology: spec-first design, dogfood testing, de-complection discipline. Documented in `docs/PLAYBOOK.md`. Conformance levels in `docs/playbook/`.

**Process Dictionary** — Per-process key-value store in Erlang. Used for dynamic scope stack (`$ability_stack`) and stateful FFI operations.

**Pull Sync** — The three-phase synchronization protocol: advertise local refs → receive remote diff → request missing definitions. Implemented in `src/gleamunison/sync.gleam`.

## R

**REPL** — Read-Eval-Print Loop. The interactive command-line interface for dogfooding the runtime. Start with `./gleamunison_escript repl`.

## S

**SHA256** — The cryptographic hash function used for content-addressing. Replaced 32-bit `erlang:phash2` in Phase 4 for collision resistance.

**Supervision Tree** — OTP process hierarchy for fault tolerance. Implemented in `src/gleamunison_sup.erl`. Workers automatically restarted on failure.

**S-Expression** — The surface syntax format: `(let x 42 (add x 1))`. Parsed by `src/gleamunison/parser.gleam`.

## T

**Type Inference** — The process of determining types without explicit annotations. Uses Hindley-Milner algorithm W. Implemented in `src/gleamunison/inference.gleam`. Includes `check_linearity/2` for continuation safety.

## G (continued)

**Guard Clause** — A condition on a match case: `(match x ((n (< n 5)) body))`. Guards are restricted to BEAM-guard-safe operations. AST `Guard` type, compiled to Erlang `when` clauses.

## H (continued)

**Hole** — An incomplete expression placeholder (`?`). First-class typed holes compile to `erlang:error({hole, ...})`, enabling live fill-and-resume workflows (Hazel paradigm).

**HTTP Client** — `gleamunison/http_client` — typed HTTP with `get`, `post`, `put`, `delete` wrapping Erlang `httpc`.

## L (continued)

**Labeled Arguments** — Sugar for curried lambdas with defaults: `(fn* ((x 1) (y 2)) body)`. Desugars to nested lambdas with let-bound defaults.

**Linearity Enforcement** — Static validation that continuation variables in algebraic effect handlers are resumed exactly once. Implemented in `check_linearity/2`.

**LSP** — Language Server Protocol. Spec documented in `docs/LSP.md`. Provides autocomplete, hover, go-to-def, diagnostics for IDE integration.

## M (continued)

**Metrics** — `gleamunison/metrics` — counter, gauge, and histogram operations emitting `:telemetry` events for Prometheus/StatsD integration.

## P (continued)

**Property-Based Testing** — Random input generation with property verification. `gleamunison_property.erl` provides `check/2` with generators (`int_gen`, `bool_gen`, `list_gen`).

## T (continued)

**Template** — `gleamunison/template` — `{{var}}` string interpolation with HTML-safe escaping against XSS.

**Trace Inspector** — Darklang-style live request capture. `gleamunison_trace.erl` stores HTTP request traces in ETS, exposed via `/api/traces` dashboard endpoints with SSE push.

**Type Alias** — Named reference to another type: `(type alias Id Int)`. `SurfaceTypeAlias` and `SurfacePubTypeAlias` control export visibility.

## U

**`use` Expression** — Monadic sugar: `(use x <- call body)` desugars to `call(fn(x) { body })`. AST `Use` variant, compiled to lambda-passing Erlang.
