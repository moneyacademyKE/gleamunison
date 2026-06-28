# Changelog

---

## What's New in v1.0.0 (2026-06-28)

Release v1.0.0 addresses critical supervisor test flakiness and transient ETS table lifetime issues.

### 1. Robust Supervisor Restart Testing
- Implemented a recursive `wait_for_restart/2` polling helper in `gleamunison_sup.erl`, replacing fragile `timer:sleep(50)` timing assumptions.
- Ensures flake-free test suite execution under high concurrency.

### 2. Supervised ETS Table Ownership
- Decoupled `gleamunison_peer_refs` named ETS table lifetime from transient RPC execution processes by initializing it under the supervisor-backed `ets_holder` worker process.
- Prevents silent table deletion when RPC calls exit.

### 3. Architectural Gap Analysis & ADRs
- Performed thorough Rich Hickey Gap Analyses for Unison 1.0 feature parity and transient ETS table lifetimes.
- Added ADR-0041 and ADR-0042 documenting these design constraints and implementations.
- Updated project learnings and design patterns playbooks.

---

## What's New in v0.9.0 (2026-06-27)

Phase 6.1 Dynamic Web Dashboard + Phase 7.1 Tagged Unions. **28 Gleam modules**, **96 source files** (4,639 lines), **1.2 MB escript**, 24 files changed (+688 / -177).

### 1. Dynamic Web Dashboard (Phase 6.1)
- **Tabbed admin UI**: 6 tabs — Overview, Modules, Processes, Definitions, Sync, Logs — with glassmorphic dark theme
- **SSE real-time push**: `GET /api/events` replaces 2s polling, broadcasts on eval/define/module-load events
- **Static file serving**: `GET /static/*` from `priv/static/` with MIME detection and path traversal protection
- **Enhanced module listing**: `/api/modules` with hashes, beam sizes, and compilation timestamps
- **Process inspector**: `/api/processes` with per-process memory, reductions, queue length, supervisor tree
- **Sync status**: `/api/sync-status` with genesis count, notebook defs, loaded modules, beam file count
- **Notebook manager**: Definition browser + editor in Definitions tab with `/define` and `/browse` endpoints
- **Activity timeline**: Logs tab + redefinition tracking via `/api/logs` and `/api/redefinitions`

### 2. Pipeline Refactoring
- **Factored pipeline**: `src/gleamunison/pipeline.gleam` — `parse_only`, `elaborate_only`, `compile_only`, `load_and_eval` exposed as discrete phases
- **ElabCtx exposed**: `elaborate_unit` now returns `#(Unit, TypeCache, ElabCtx)` — third element provides symbol/type/ability metadata for LSP
- **Backward compatible**: `repl_eval.do_eval` and `handle_define` unchanged, all 1000 dogfood levels pass

### 3. Tagged Unions (Phase 7.1)
- **`Construct` term**: `(MyType arg1 arg2)` — builds values of custom types, emits Erlang tuples
- **`PatConstructor` pattern**: `(MyType pat1 pat2)` in match cases — destructures custom types
- **Type definition syntax**: `(type TypeName ctor1 ctor2 ...)` parsed as surface form
- **Full pipeline support**: parser → elaboration → inference → compilation → codebase hashing — all layers handle new variants

### 4. Documentation
- **38 ADRs** (+4 new: 0035 lexer-parser separation, 0036 benchmarking, 0037 REPL decomposition, 0038 type pretty-printing)
- **LICENSE** (MIT), **CONTRIBUTING.md**, **scripts/README.md**, **docs/BUILD_ESCRIPT.md**, **docs/genesis-modules.md**, **docs/GLOSSARY.md**
- **Updated**: README (28 modules, 96 files, 4,639 lines), ARCHITECTURE (Phase 5 sections), MANUAL (concurrency, distributed, dashboard), ROADMAP (Phases 6-10)

### Running
```
./gleamunison_escript server   # Web dashboard at http://localhost:8080
./gleamunison_escript repl     # Interactive REPL
gleam run -- all               # 1000 dogfood levels
```

---

## What's New in v0.8.0 (2026-06-27)

Phase 5 production release: distributed topology, concurrency primitives, community library integrations, and dogfood toolchain. **189 BEAM modules**, **1.1 MB escript**, **32 gleam source files** (436 KB), 80 files changed (+7822 / -5896).

### 1. Distributed Topology & Concurrency (Phase 5)
- **Concurrency primitives**: `spawn`, `send`, `recv`, `self`, `sleep`, `now` operations
- **Remote ability**: `forkAt`, `await`, `here` — location-transparent distributed compute
- **Mnesia storage adapter**: ACID replicated codebase storage across clustered nodes
- **Supervision trees**: `gleamunison_sup` — OTP supervisor with isolated link topology for test runners

### 2. Parser & REPL Upgrades
- **Multi-line REPL**: bracket-counting accumulator with spelling suggestions via depth-limited Levenshtein
- **Parser split**: lexer separated from parser for independent testing and extension
- **Escaped quotes**: tokenizer-level escape sequence awareness for nested JSON-like strings
- **Syntax additions**: `;` comments, `+` operator alias, `'` quote reader macro
- **Pipe deadlock fixes**: stderr stream inheritance in subprocess runners

### 3. Builtins & Abilities
- **Math/Show abilities**: typed arithmetic and display operations
- **FFI builtins**: `json-parse`, `http-get`, `file-read` — all via genesis hash-addressing
- **State ability bootstrapping**: handler stack composition for mutable state

### 4. Community Library Integrations
- **simplifile**: typed file I/O operations
- **glam**: pretty-printer layout engine
- **birdie**: snapshot testing framework
- **gleamy_structures**: Bimap and PriorityQueue persistent data structures

### 5. Infrastructure
- **Test runner**: timeout support, FFI split, help command, test suite recovery
- **Stub generation**: starting at level 1, `all` command to run every level
- **SHA256 identity**: upgraded from 32-bit phash2 to 256-bit cryptographic hashes
- **34 ADRs**: complete Architecture Decision Record catalog with index

---

## What's New in v0.7.0 (2026-06-27)

1000-level dogfood playbook completion. **113 BEAM modules**, **671 KB escript**, 114 beam files.

### 1. Genesis Modules & Dogfood Completion
- **30 new genesis modules**: string ops (10), list ops (10), data structures (pair/fst/snd, either, dict, set)
- **1000 dogfood levels**: full playbook certification suite in `src/dogfood.gleam`
- **10-file playbook split**: `docs/playbook/` with Results + Location metadata on every level
- **Full CLI dispatch**: `gleam run -- levelN` and `gleam run -- all`

### 2. REPL & Interactive Features
- **Interactive REPL**: read-eval-print loop with dynamic module purging
- **Curried dynamic dispatch**: `erlang:apply/2` for nested function applications
- **Console algebraic effects**: print/read operations via effect handlers
- **Module purging**: explicit `code:delete/1` and `code:purge/1` on redefinition

### 3. Parser Features
- **Handle syntax fix**: arity mismatch resolved with lambda wrapping
- **Multi-line REPL support**: bracket-aware line accumulation
- **Float literal parsing**: through tokenizer, parser, and compilation pipeline
- **Unique module names**: fix concurrent `/eval` race conditions

### 4. Infrastructure
- **Self-contained escript**: `build_escript.sh` compiles raw `.erl` genesis modules
- **HTTP server dashboard**: embedded web server for live node state inspection
- **Stateful/file FFI**: process-dictionary-backed mutable state and file operations

---

## What's New in v0.6.0

Runtime robustness safeguards across storage, module lifecycle, and dynamic scope stacks. All files strictly under 150 LOC.

### 1. Hash-Partitioned DETS Storage
- **Durable Prefix-Splitting**: Dynamically splits key-value storage across 16 DETS partition files (`db_0.dets` to `db_f.dets`) based on hash key prefix. Bypasses the DETS 2GB limit, supporting up to 32GB of native KV storage.
- **Directory Lifecycle Control**: Exposes `partitioned_dets_delete` routines for segmented file purges during testing.

### 2. LRU Module Purging
- **Atom Table & Memory Guards**: LRU cache tracking module accesses. Evicts least-recently-used modules when exceeding capacity (default 1000).
- **VM Unloader**: Explicit `code:delete/1` and `code:purge/1` FFI unloads on evicted BEAM binaries to prevent memory leaks.

### 3. Dynamic Stack Safety Validation
- **Format Integrity Checks**: `validate_stack` and `validate_handler` on every push/pop operation on the process dictionary `$gleamunison_handlers` stack.
- **Clear Exceptions**: Throws debuggable Erlang exceptions instead of silent badmatches on stack corruption.

### 4. Coordinate Tokenizer & Diagnostics
- **Offset Tracking**: Tracks line and column positions dynamically during lexing passes.
- **Diagnostics Propagation**: Precise coordinate references in `ParseError` objects.

---

## What's New in v0.5.0

This release implements the core production roadmap components: persistent storage, cryptographic hashing, and a surface syntax parser, while maintaining all files strictly under the 150 LOC limit.

### 1. DETS Persistent Storage
- **Disk Durability**: Added a disk-based storage backend utilizing Erlang's native `dets` engine. Serialized definition bytes are stored on disk, allowing codebases to survive node restarts.
- **Lifecycle Management**: Equipped `StorageAdapter` with a `close` command to cleanly release table locks, preventing slow table repair cycles on subsequent opens.
- **Test Isolation**: Exposed `dets_delete_file` FFI helper to clear test files dynamically, ensuring test purity.

### 2. SHA256 Cryptographic Identity
- **Collision Resistance**: Replaced volatile 32-bit `erlang:phash2` with 256-bit SHA256 hashes generated by Erlang's OpenSSL-backed `crypto` module.
- **Genesis Alignment**: Padded built-in genesis hashes (`builtin_int_add` and `builtin_io_read_line`) to match the 256-bit boundary, establishing a consistent hash length throughout all codebase lookups.

### 3. S-Expression Surface Parser
- **Syntax Parsing**: Implemented a pure, zero-dependency S-expression lexer and parser (`parser.gleam`) in under 110 lines of code.
- **AST Mapping**: Compiles standard symbol and nested list strings (such as `(let x 42 (lam y (add x y)))`) directly into the compiler's `SurfaceTerm` representation.

---

## What's New in v0.4.0

This release resolves 18 critical bugs in serialization, storage persistence, dynamic effect handler scoping, synchronization logic, and type checking, while strictly maintaining the <100 LOC limits across all Gleam and Erlang files.

### 1. Robust Storage & Sync Persistence
- **Sync Persistence (BUG-54)**: Pulled sync definition blobs are now persisted to the codebase storage adapter and cached in the seen dictionary rather than being discarded.
- **Persistence Verification (BUG-55)**: Correctly calls `codebase.adapter.insert` with serialized definition bytes (via `string.inspect/1` serialization) on all insertion operations.
- **Key-Value Push Protocol (BUG-56)**: Upgraded `push_sync` and `sync_push_defs` to transmit keyed tuples `List(#(String, BitArray))` instead of anonymous binaries, enabling correct hash mapping on remote nodes.

### 2. Alpha-Equivalence & Inference
- **Alpha-Equivalence Checking (BUG-45/57)**: Implemented sequential type variable index normalization in `infer_helper.gleam` to compare polymorphic types alpha-equivalently, resolving false type mismatches in both definition typechecking and homogeneous lists.
- **Sequential TVar Lowering (BUG-52)**: Dynamically threads type variable assignments during lowering to output unique de Bruijn indices.
- **Enhanced Effect Type Inference (BUG-41/53)**: Injects `TypeVar(-1)` fallback sentinels and infers accurate output types for `Do` operations (from cache), `Handle` computations, and `Match` bodies.
- **Structural Hashing Fallbacks (BUG-42/43)**: Structural hashing support for `Match`/`Do`/`Handle` terms and function/app types.

### 3. FFI & Effects VM
- **Keyed Effect Handler (BUG-40)**: Modified compiler to emit handlers wrapped in ability-keyed tuples `{'m_XXXXXX', Handler}` for dynamic stack lookup.
- **Safe Map Lookup (BUG-50)**: Replaced unchecked map pattern matches with nested safe case expressions in Erlang dispatcher.
- **Gleamunison boot entry**: Changed `main` function signature in `gleamunison.gleam` to accept command line args list (`main(_args: List(String))`) so escript boots directly to `gleamunison:main/1` without clashing.
- **LOC Restructuring**: Decomposed helper modules to `infer_helper.gleam` and `gleamunison_ffi_test.erl` to keep all codebase files strictly under 100 lines.

---

## Verification Results
- **Test Suite**: 34 passing unit/integration tests covering alpha-equivalence, persistence database roundtrips, loader memoization, and FFI test runners.
- **Compilation**: 100% warning-free Gleam and Erlang compilation.

---

## What's New in v0.3.0

This release completes Phase 0/1 of the prototype, delivering an integrated, end-to-end Content-Addressed VM with Hindley-Milner type inference, lexically scoped algebraic effects, dynamic BEAM bytecode compilation & hot code loading, and a three-phase pull sync protocol.

### 1. Robust Core VM & Type System
*   **Hindley-Milner Type Inference**: Support for Int, Float, Text, homogeneous Lists, and multi-argument curried application.
*   **Polymorphic sentinel**: Introduces a dedicated `TypeVar(-1)` sentinel for unknown apply evaluations, preventing index collisions with local binders.
*   **Structural Content-Addressability**: Complete hash-addressed codebase. Hashing of type declarations and ability declarations is structurally serialized using deterministic inspect logic, ensuring unique identity and zero collisions.

### 2. Lexically Scoped Algebraic Effects
*   **Process Dictionary Handler Stack**: Effect handlers are dynamically managed on a thread-local stack in the process dictionary.
*   **Erlang Effects Dispatcher (`gleamunison_effets.erl`)**: Fully implements dynamic `do_op/4` and `handle_comp/2` with trailing-block call semantics and key normalization (matching both atom and binary keys).
*   **Exception Safety**: Employs `try ... after` blocks to guarantee stack restoration in case of runtime computation errors.

### 3. Isolated Content-Addressed Storage
*   **Erlang ETS-backed storage**: Implemented inside `gleamunison_storage.erl`.
*   **Background process ownership**: Spawns an unsupervised background thread to permanently hold table memory. Data survives caller process terminations (e.g. transient web requests or unit test workers).

### 4. 3-Phase Pull-based Sync Protocol
*   **Protocol Flow**: Advertise local refs → receive remote diff → request missing definitions.
*   **Hash Integrity**: Received payloads transmit `(hash_hex, compiled_beam)` pairs, enabling the receiver to hex-decode and reconstruct the canonical `DefinitionRef` directly instead of incorrectly hashing compiled bytecode.

### 5. Packaging & standalone binary
*   **Standalone escript**: Packages all compiled BEAM bytecode (including dependencies like `gleam_stdlib`) into a single executable `gleamunison` (~350KB).
*   **Zero dependencies**: Runs on any machine with Erlang/OTP installed, without requiring Gleam at runtime.

---

## Verification Results (v0.3.0)
*   **Test Suite**: 26 passed unit and integration tests covering codebase hashing, sync diffing, effect stack execution, and storage lifecycle.
*   **Constraint Verification**: 100% compliance with the strict codebase limit of <100 lines per `.gleam` file.
