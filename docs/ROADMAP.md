# Production Roadmap

From architectural specification to production-grade content-addressed runtime.

**Current state:** All 12 source modules implemented and running on OTP 29.
~1,450 lines of Gleam, ~200 lines of Erlang FFI. Full pipeline from AST →
Hash → Codebase → Compile → Load → Execute.

---

## Phase 0: Genesis bootstrap ✓

**Goal:** A working pipeline end-to-end.

### Status: COMPLETE

- **0.1 Core types compile** — All 12 source modules compile cleanly with
  `gleam check`. Circular dependency between `ast` and `types` resolved by
  co-locating `Type` in `ast.gleam`.
- **0.2 Minimal codebase** — `inmemory()` adapter with `Dict`, `hash_of_definition`
  using `erlang:phash2`, hash verification on insert.
- **0.3 Minimal elaborator** — SurfaceTerm → core Term with de Bruijn assignment,
  name resolution, ability lookup.
- **0.4 Minimal type checker** — `infer_term` handles Int/Float/Text/List,
  returns `Result(Type, InferenceError)`.
- **0.5 Minimal compiler** — `emit_term/1` handles all 7 Term variants (Int,
  Float, Text, RefTo, LocalVarRef, Apply, Lambda, Let, Match, List). Generates
  Erlang source → `compile:file/2` → BEAM binary.
- **0.6 Minimal loader** — `ensure_loaded` checks loaded/failed sets, compiles,
  calls `code:load_binary/3`.
- **0.7 Integration test** — Full pipeline runs in `gleam run`:
  `Hash: 04cc725a → Store: OK → Compile: OK → Load: OK`

### Key fixes discovered:
- `compile:file/2` OTP 29 returns `{ok, Mod, []}` — file readback pattern
- `m_` prefix instead of `@` for module names (ADR-0011)
- Escript packaging via header+zip (ADR-0013)
- Gleam v1.0+ strings are UTF-8 binaries
- `erlang:type/1` removed in OTP 29

---

## Phase 1: Core language runtime ✓

**Goal:** Run programs with functions, types, and algebraic effects.

### Status: IMPLEMENTED

- **1.1 Full term compilation** — All Term variants compile: Match, Case,
  List, Text, Float, Lambda (BEAM fun closures), Let, Apply.
- **1.2 Ability declarations + handlers** — `Do` and `Handle` in AST, compile
  generates `gleamunison_effets:do_op/4` and `handle_comp/2` calls.
- **1.3 Dynamic scope stack** — `gleamunison_effets.erl`: process dictionary
  stack, push_frame/pop_frame/find_frame, op_N auto-discovery.
- **1.4 Ambient handlers** — `RuntimeConfig` type, `HandlerFrame`/`OpHandler`.
- **1.5 Stateful handlers** — Type definitions in `effects.gleam`.
- **1.6 Type declarations** — `Structural`/`Unique` types, `Constructor` in AST.
- **1.7 Integration test** — All pipeline steps verified in `gleam run`.

---

## Phase 2: Surface language and tooling

**Goal:** Accept a text-based surface language, not just AST construction in Gleam.

### Status: Types and elaboration implemented. Parser and REPL are future work.

- **2.1 Surface syntax parser** — `elaborate.gleam` has all surface types
  (SurfaceTerm with 7 constructors, SPattern, SurfaceUnit). Surface → core
  elaboration with name resolution, ability lookup, de Bruijn assignment.
  Recursive descent parser for s-expressions is ~200 lines of future work.
- **2.2 REPL loop** — Future work.
- **2.3 Error messages** — Error types defined for all phases: `CompileError`,
  `InsertError`, `InferenceError`, `HandlerError`, `ElaborateError`, `LoaderError`,
  `SyncError`, `ConnectError`.

---

## Phase 3: Persistence and distribution

**Goal:** Codebase survives restarts. Multiple nodes can share definitions.

### Status: Types implemented. DETS/Mnesia backends and sync runtime are future work.

- **3.1 Persistent storage adapters** — Implement DETS and SQLite adapters to store serialized definition bytes on disk, replacing the purely in-memory ETS table.
- **3.2 Mnesia storage adapter** — Future work.
- **3.3 Pull-based sync** — `SyncState`, `PeerState`, `pull_sync`, `push_sync` with Erlang distribution FFI stubs.
- **3.4 Namespace management** — Future work.

---

## Phase 4: Production hardening

**Goal:** Reliable, observable, performant.

### Status: Design documented. Implementation is future work.

- **4.1 In-memory Abstract Format compilation** — Generate Erlang Abstract Format in memory and compile using `compile:forms/2` to eliminate temporary file system I/O latency.
- **4.2 Cryptographic Hash migration** — Migrate from 32-bit `phash2` to 512-bit Blake2b or SHA3 to eliminate hash collision risks.
- **4.3 Full Hindley-Milner solver** — Upgrade the type substitution engine to a stateful constraint-solving algorithm (Algorithm W) to support complex type variables inference.
- **4.4 Process Dictionary stack protection** — Wrap process dictionary operations in safe wrapper APIs or migrate to process-local state holders to prevent manual dictionary corruption.
- **4.5 Telemetry and Supervision** — Supervision trees, dynamic module unloading, and observability telemetry.

---

## Phase 5: Ecosystem

**Goal:** Usable by developers beyond the original author.

### Status: Future work.

- Package management, LSP, documentation, remote computation.

## Risk register

| Risk | Likelihood | Status |
|---|---|---|
| Erlang FFI complexity (compile, load_binary) | Medium | **Resolved** — OTP 29 patterns documented |
| Compilation speed for large codebases | Medium | Not yet measured |
| Atom table exhaustion | Low | `m_` prefix mitigates |
| Process dictionary stack corruption | Low | try/catch in effects runtime |
| Hash collisions (phash2) | High | Prototype only; Blake2b for production |
| Stateful handler gen_server bottleneck | Low | Not yet implemented |
