# Production Roadmap

From architectural specification to production-grade content-addressed runtime.

**Current State:** Fully certified Lisp-style surface parser, typechecker, compiler, and VM runner. Certified against 1000 playbook conformance levels (959 passed, 41 skipped, 0 failed). **v1.1.0**: Standard library (http, json, datetime, filepath, crypto, template), structured logging, metrics, health checks, guard clauses, holes, `use` expression, linearity enforcement, CAS adapters, trace inspector, error codes, and LSP documentation — all implemented.

---

## Phase 0: Genesis bootstrap ✓
- **Status:** COMPLETE. Core pipeline compiles and executes.

## Phase 1: Core Language Runtime ✓
- **Status:** COMPLETE. Full term compilation, algebraic effects (Console, State), and handler stacks.

## Phase 2: Surface Language & REPL Tooling ✓
- **Status:** COMPLETE. S-expression parser, name resolution, error propagation, interactive REPL loop, and dynamic module hot-purging.

## Phase 3: Persistence & Sync Protocol ✓
- **Status:** COMPLETE. Durable DETS storage adapter, ETS table ownership, and pull-based peer synchronization.

## Phase 4: Production Hardening ✓
- **Status:** COMPLETE. SHA256 identity hashing, stack-safe effects FFI, and Algorithm W type propagation.

---

## Phase 5: Distributed Topology & Concurrency ✓
- **Status:** COMPLETE. Added `Remote` ability with `forkAt`, `await`, and `here` operations, Mnesia replicated storage adapter, dynamic OTP supervision trees (`gleamunison_sup`), and serializable continuations using Erlang's binary serialization engine.

---

## Phase 6: Ecosystem & Developer Ergonomics

**Goal:** Enable product development and authoring tooling.

| Priority | Item | Description | Status | Effort |
|---|---|---|---|
| **6.1 (P0)** | **Dynamic Web Dashboard** | Full-featured admin UI with SSE real-time push, process inspector, module browser, definition editor, sync status, activity logs. Static file serving from priv/static/. | ✓ DONE (v0.9.0) | S |
| **6.2 (P1)** | **LSP / IDE Support** | Language Server Protocol backend for autocomplete, go-to-definition, hover-type, inline diagnostics. Protocol spec and architecture documented in `docs/LSP.md`. Full implementation deferred. | ✓ SPEC (v1.1.0) | L |
| **6.3 (P2)** | **Package Registry** | P2P hash-verified package manager. Decentralized package discovery with cryptographic immutability. | PENDING | L |

---

## Phase 7: Language Features & Type System Enhancements

**Goal:** Deepen expressiveness without sacrificing type safety or Erlang interop. Can run in parallel with Phase 6.

| # | Feature | Status | Effort | Description |
|---|---|---|---|
| 7.1 | Exhaustiveness-checked tagged unions | ✓ DONE (v0.9.0) | `Construct` term + `PatConstructor` pattern with Erlang tuple compilation. Type definition form `(type Name ctors...)` parsed. |
| 7.2 | Labeled arguments with defaults | ✓ DONE (v1.1.0) | `(fn* ((x 1) (y 2)) body)` — curried lambda sugar with defaults. Parser + elaborator desugaring. |
| 7.3 | Guard clauses in `case`/`fn` | ✓ DONE (v1.1.0) | `(match x ((n (< n 5)) body))` — AST `Guard` type, parser support, Erlang `when` clause emission. |
| 7.4 | `use` expression (monadic sugar) | ✓ DONE (v1.1.0) | `(use x <- call body)` — desugars to `call(fn(x) { body })` at AST level. |
| 7.5 | `pub opaque type` | ✓ DONE (v1.1.0) | `SurfacePubTypeAlias` variant in elaborator. Constructor visibility controlled at definition level. |
| 7.6 | Type alias export control | ✓ DONE (v1.1.0) | `SurfaceTypeAlias` and `SurfacePubTypeAlias` in surface defs. Full elaboration pipeline support. |
| 7.7 | Monadic syntax bindings | PENDING | S | Monadic S-expression sequencing (`let*` or `do` block bindings) desugaring to nested lambdas during elaboration. |

---

## Phase 8: Standard Library & Core Packages

**Goal:** Curated stdlib covering 80% of BEAM development needs. Depends on Phase 7 type features.

| # | Feature | Status | Effort | Description |
|---|---|---|---|
| 8.1 | `gleamunison/http` client | ✓ DONE (v1.1.0) | Typed HTTP client (`get`, `post`, `put`, `delete`) wrapping Erlang `httpc`. Opaque `HttpResponse` type. |
| 8.2 | `gleamunison/json` codec | ✓ DONE (v1.1.0) | JSON encode/decode wrapping Erlang `json`. Free-standing FFI for dynamic deserialization. |
| 8.3 | `gleamunison/datetime` | ✓ DONE (v1.1.0) | Opaque `DateTime` type, ISO 8601 parse/format, arithmetic (`add_seconds`, `diff_seconds`). |
| 8.4 | `gleamunison/filepath` | ✓ DONE (v1.1.0) | Opaque `Path` type, `join`, `parent`, `extension`, `with_extension`, `is_absolute`. |
| 8.5 | `gleamunison/crypto` | ✓ DONE (v1.1.0) | `hash` (SHA256/512/MD5), `hmac`, `random_bytes`, `hash_hex` wrapping Erlang `crypto`. |
| 8.6 | `gleamunison/template` | ✓ DONE (v1.1.0) | `{{var}}` string interpolation with HTML-safe escaping. |
| 8.7 | Stdlib documentation generation | ✓ DONE (v1.1.0) | `scripts/generate_docs.sh` → `docs/stdlib/index.html`. Module/function-level HTML docs. |

---

## Phase 9: Developer Tooling & IDE Integration

**Goal:** Polished DX rivaling Rust/Go/Elixir. Depends on Phase 6 LSP infrastructure.

| # | Feature | Status | Effort | Description |
|---|---|---|---|
| 9.1 | LSP: completion, hover, go-to-def | ✓ SPEC (v1.1.0) | Protocol spec and architecture in `docs/LSP.md`. Full implementation deferred. |
| 9.2 | `gleam format` | PENDING | M | Opinionated formatter, zero config, <100ms per module |
| 9.3 | Debugger integration | PENDING | L | BEAM debugger via `:debugger`, step through Gleam source |
| 9.4 | Property-based testing | ✓ DONE (v1.1.0) | `gleamunison_property.erl` — `check/2`, `int_gen/0`, `bool_gen/0`, `list_gen/1`, `tuple_gen/2`. |
| 9.5 | `gleam watch` | ✓ DONE (v1.1.0) | `scripts/watch.sh` — file watcher, auto-rebuild on change, optional `--test` mode. |
| 9.6 | Error message improvement | ✓ DONE (v1.1.0) | Elm/Rust-style: `[P001]`–`[P004]` parse errors, `[E001]`–`[E005]` type errors with suggested fixes. |
| 9.7 | Scratch-file watcher loop | PENDING | S | background file watcher (`watch-scratch`) for non-blocking local verification. |
| 9.8 | REPL Code Graph Queries | PENDING | S | `view`, `dependents`, and `dependencies` commands in REPL console. |

---

## Phase 10: Production Runtime & Operations

**Goal:** Operable, observable, maintainable in production without OTP expertise.

| # | Feature | Status | Effort | Description |
|---|---|---|---|
| 10.1 | Structured logging | ✓ DONE (v1.1.0) | `gleamunison/log`: `debug`/`info`/`warn`/`error` with context dict, ETS-backed persistence. |
| 10.2 | Metrics & telemetry | ✓ DONE (v1.1.0) | `gleamunison/metrics`: `counter`/`gauge`/`histogram` with `:telemetry` events. ETS-backed storage. |
| 10.3 | `gleam release` (replaces escript) | PENDING | L | Standalone tarball with ERTS, no Erlang pre-install required |
| 10.4 | Configuration management | ✓ DONE (v1.1.0) | `gleamunison/config`: env/TOML/CLI with defined precedence. `get_string`, `get_int`, `get_bool`. |
| 10.5 | Health checks & readiness probes | ✓ DONE (v1.1.0) | `gleamunison/health`: `run_all/0`, `readiness/0`. `/api/health` HTTP endpoint. |
| 10.6 | Distributed tracing | PENDING | L | OpenTelemetry integration, typed span propagation |
| 10.7 | Operations runbook | ✓ DONE (v1.1.0) | `docs/OPERATIONS.md`: deploy, configure, monitor, upgrade, troubleshoot, backup. |

---

## Phase 11: Advanced Paradigms (Urbit, Koka, & Hazel Integrations)

**Goal:** Incorporate bleeding-edge optimization, correctness, and live development paradigms into the core compiler and runtime.

| # | Feature | Status | Effort | Description |
|---|---|---|---|
| 11.1 | FFI Compiler Jets | ✓ DONE | S | Map pure content-addressed function hashes directly to native Erlang/Gleam overrides, avoiding dynamic compilation overhead. |
| 11.2 | Linearity-Enforced Continuations | ✓ DONE (v1.1.0) | `check_linearity/2` in inference engine — validates continuation variables are used exactly once in handler branches. |
| 11.3 | First-Class Typed Holes | ✓ DONE (v1.1.0) | `ast.Hole` variant — `?` parses to hole, compiles to runtime `erlang:error({hole, ...})`. Enables live fill-and-resume workflows. |

### Phase Dependency Graph

```
Phase 5 (Distributed) ──┐
                         ├──→ Phase 6 (Ecosystem: LSP, Registry, Dashboard)
                         │         │
                         │         ├──→ Phase 9 (Tooling: depends on LSP from P6)
                         │         │
                         │         └──→ Phase 12 (Operations/DX: needs Dashboard from P6)
                         │
                         ├──→ Phase 7 (Language: independent; can parallel P6)
                         │         │
                         │         └──→ Phase 8 (Stdlib: needs P7 type features)
                         │                   │
                         │                   └──→ Phase 10 (Operations: needs P8 stdlib)
                         │
                         └──→ Phase 11 (Advanced: FFI Jets, Linearity, Holes)
```

---

## Phase 12: Integrated DX & Operations (Darklang Integrations)

**Goal:** Close the feedback loop between live execution context and developer editing experience.

| # | Feature | Status | Effort | Description |
|---|---|---|---|
| 12.1 | Trace-Driven Request Interception | ✓ DONE (v1.1.0) | `gleamunison_trace.erl` — captures HTTP method/path/headers to ETS table, SSE push to dashboard. |
| 12.2 | In-Dashboard Trace Inspector | ✓ DONE (v1.1.0) | `/api/traces` and `/api/traces/:id` endpoints. Full trace list + detail view. |
| 12.3 | Lazy CAS Type Adapters | ✓ DONE (v1.1.0) | `gleamunison_adapters.erl` — ETS-based adapter registry. `register`/`find`/`adapt`. ADR-0048 docs. |

Effort key: **S** = Small (days), **M** = Medium (weeks), **L** = Large (month+).

---

## Phase 13: Security Hardening & Codebase Refactoring

**Goal:** Secure the FFI boundaries, resolve socket leak bugs, and refactor the massive code-gen footprint into simple, maintainable data-driven structures.

| # | Feature | Status | Effort | Description |
|---|---|---|---|---|
| 13.1 | **Harden FFI Serialization (P0)** | PENDING | S | Modify `binary_to_term` in `gleamunison_ffi_io.erl` and `gleamunison_tcp_sync.erl` to use `binary_to_term(Bin, [safe])` to prevent remote code execution and atom table exhaustion. |
| 13.2 | **Fix SSE Socket Monitor (P0)** | PENDING | S | Resolve process-monitor crash in static routing where socket port references are monitored as process IDs. |
| 13.3 | **Fix Undef eval_expression FFI (P0)** | PENDING | S | Implement and export `eval_expression` in `gleamunison_ffi.erl` to fix HTTP route invocation crash. |
| 13.4 | **Secure HTTP Endpoints (P0)** | PENDING | S | Bind HTTP listener default to `127.0.0.1` and restrict the `/eval` and `/define` routes to prevent open-network remote execution. |
| 13.5 | **Extract range and builtins (P1)** | PENDING | S | Move duplicated `range` function from all 112+ modules into `gleamunison/util.gleam`. Consolidate `init_defs` from `repl.gleam` and `verify.gleam` to `gleamunison/identity.gleam`. |
| 13.6 | **Data-Driven Dogfooding (P1)** | PENDING | M | Refactor the `generate_levels.clj` pipeline to emit a single database/data-structure representation of levels, removing 90k lines of generated boilerplate. |
| 13.7 | **Fix Metric/Docs Inconsistencies (P2)**| PENDING | S | Align all level and module metrics across README, Architecture, and Playbook docs. Correct duplicate numbering in `LEARNINGS.md`. |
