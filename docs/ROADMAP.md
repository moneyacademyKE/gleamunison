# Production Roadmap

From architectural specification to production-grade content-addressed runtime.

**Current State:** Fully certified Lisp-style surface parser, typechecker, compiler, and VM runner. Certified against 1000 playbook conformance levels (959 passed, 41 skipped, 0 failed).

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
| **6.2 (P1)** | **LSP / IDE Support** | Language Server Protocol backend for autocomplete, go-to-definition, hover-type, inline diagnostics. Enables VS Code/Helix/Vim integration. | PENDING | L |
| **6.3 (P2)** | **Package Registry** | P2P hash-verified package manager. Decentralized package discovery with cryptographic immutability. | PENDING | L |

---

## Phase 7: Language Features & Type System Enhancements

**Goal:** Deepen expressiveness without sacrificing type safety or Erlang interop. Can run in parallel with Phase 6.

| # | Feature | Status | Effort | Description |
|---|---|---|---|
| 7.1 | Exhaustiveness-checked tagged unions | ✓ DONE (v0.9.0) | `Construct` term + `PatConstructor` pattern with Erlang tuple compilation. Type definition form `(type Name ctors...)` parsed. |
| 7.2 | Labeled arguments with defaults | S | `fn connect(host host: String, port port: Int := 5432)` — zero-cost sugar |
| 7.3 | Guard clauses in `case`/`fn` | M | `case x { Some(n) if n > 0 -> ... }` — restricted to BEAM-guard-safe ops |
| 7.4 | `use` expression (monadic sugar) | L | `use conn <- websocket.upgrade(req)` — Gleam's `use` proposal, single-form sugar |
| 7.5 | `pub opaque type` | M | Constructors not exported; pattern matching only via provided functions |
| 7.6 | Type alias export control | S | `pub type alias Id = Int` vs private `type alias Id = Int` |

---

## Phase 8: Standard Library & Core Packages

**Goal:** Curated stdlib covering 80% of BEAM development needs. Depends on Phase 7 type features.

| # | Feature | Status | Effort | Description |
|---|---|---|---|
| 8.1 | `gleamunison/http` client | M | Typed HTTP client, builder pattern, owned types |
| 8.2 | `gleamunison/json` codec | L | JSON encode/decode with automatic codec derivation for custom types |
| 8.3 | `gleamunison/datetime` | M | Typed Date/Time/DateTime/Duration, ISO 8601 |
| 8.4 | `gleamunison/filepath` | S | Typed path manipulation, never raw strings |
| 8.5 | `gleamunison/crypto` | S | Thin typed wrapper over Erlang `crypto` |
| 8.6 | `gleamunison/template` | S | Compile-time safe string interpolation |
| 8.7 | Stdlib documentation generation | S | Module/function-level doc comments, HTML gen |

---

## Phase 9: Developer Tooling & IDE Integration

**Goal:** Polished DX rivaling Rust/Go/Elixir. Depends on Phase 6 LSP infrastructure.

| # | Feature | Status | Effort | Description |
|---|---|---|---|
| 9.1 | LSP: completion, hover, go-to-def | L | Context-aware autocomplete, type-on-hover, cross-module navigation |
| 9.2 | `gleam format` | M | Opinionated formatter, zero config, <100ms per module |
| 9.3 | Debugger integration | L | BEAM debugger via `:debugger`, step through Gleam source |
| 9.4 | Property-based testing | M | PropEr/Quviq-style property testing |
| 9.5 | `gleam watch` | S | File watcher, recompile + rerun tests on change |
| 9.6 | Error message improvement | S | Elm/Rust-style: problem + reason + suggested fix with error codes |

---

## Phase 10: Production Runtime & Operations

**Goal:** Operable, observable, maintainable in production without OTP expertise.

| # | Feature | Status | Effort | Description |
|---|---|---|---|
| 10.1 | Structured logging | S | `gleamunison/log`: structured JSON, levels, context, pluggable backends |
| 10.2 | Metrics & telemetry | M | Typed `:telemetry` wrapper, Prometheus/StatsD reporters |
| 10.3 | `gleam release` (replaces escript) | L | Standalone tarball with ERTS, no Erlang pre-install required |
| 10.4 | Configuration management | S | Typed config from env/TOML/CLI with defined precedence |
| 10.5 | Health checks & readiness probes | S | Standardized health infrastructure, K8s-aware endpoints |
| 10.6 | Distributed tracing | L | OpenTelemetry integration, typed span propagation |
| 10.7 | Operations runbook | S | `docs/OPERATIONS.md`: deploy, configure, monitor, upgrade, troubleshoot |

---

## Phase 11: Advanced Paradigms (Urbit, Koka, & Hazel Integrations)

**Goal:** Incorporate bleeding-edge optimization, correctness, and live development paradigms into the core compiler and runtime.

| # | Feature | Status | Effort | Description |
|---|---|---|---|
| 11.1 | FFI Compiler Jets | ✓ DONE | S | Map pure content-addressed function hashes directly to native Erlang/Gleam overrides, avoiding dynamic compilation overhead. |
| 11.2 | Linearity-Enforced Continuations | PENDING | M | Statically verify at typecheck time that captured continuation variables `k` are resumed exactly once, preventing stack corruption. |
| 11.3 | First-Class Typed Holes | PENDING | M | Support holes `?` as membranes. Compile code with holes to runtime suspensions, allowing interactive fill-and-resume workflows. |

### Phase Dependency Graph

```
Phase 5 (Distributed) ──┐
                         ├──→ Phase 6 (Ecosystem: LSP, Registry, Dashboard)
                         │         │
                         │         └──→ Phase 9 (Tooling: depends on LSP from P6)
                         │
                         ├──→ Phase 7 (Language: independent; can parallel P6)
                         │         │
                         │         └──→ Phase 8 (Stdlib: needs P7 type features)
                         │                   │
                         │                   └──→ Phase 10 (Operations: needs P8 stdlib)
                         │
                         └──→ Phase 11 (Advanced: FFI Jets, Linearity, Holes)
```

Effort key: **S** = Small (days), **M** = Medium (weeks), **L** = Large (month+).

