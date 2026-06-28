# Gleamunison Architecture

## Overview
gleamunison is a content-addressed language runtime with algebraic effects running on the Erlang BEAM, implemented in Gleam.
1. **Content-addressed code**: identity = SHA256 hash of serialized AST.
2. **Algebraic effects**: dynamic scope dispatch with resumable continuations via process dictionary.
3. **BEAM runtime**: hot code swapping, process isolation, and OTP 29 compatibility.
4. **Standard Library**: typed modules for http, json, datetime, filepath, crypto, template.
5. **Production Operations**: structured logging, metrics/telemetry, health checks, config management.

## Pipeline
```
Text (S-Expr) → AST (Gleam types) → Hash (SHA256) → Codebase (DETS/in-mem)
                                                    → Compile (Erlang → BEAM)
                                                    → Load (code:load_binary)
                                                    → Call $eval()
```

## Component Flow

### 1. Identity & Hashing
```
AST → Serialize → crypto:hash(sha256) → Hash (256-bit) → DefinitionRef
```
The hash IS the identity. Uses Erlang's built-in crypto module to generate 256-bit OpenSSL-backed SHA256 hashes. Genesis stubs are padded to the 256-bit boundary (`<<1:256>>`). Includes hashing for Guard, Hole, and Use AST variants.

### 2. Codebase Storage
Pluggable storage adapter supporting:
- `inmemory()`: volatile ETS-backed storage.
- `dets(path)`: durable disk-based storage with clean `close` and `dets_delete_file` controls.
- `mnesia(table)`: ACID replicated storage across clustered nodes.
- `partitioned_dets(path)`: hash-prefix split across 16 partition files (up to 32GB).
- **CAS Type Adapters**: `gleamunison_adapters.erl` — ETS-based registry mapping old→new type hashes for lazy schema migration.

### 3. Compilation & Loading
- **Compiler**: `emit_term` concatenates Erlang source code from AST, invoking `compile:file/2`. Supports all Term variants including Guard clauses (Erlang `when`), Hole (`erlang:error`), and Use (lambda-passing desugaring).
- **FFI Jets**: Pre-loaded native functions mapped to content-addressed hashes via `gleamunison_jets.erl`, bypassing dynamic compilation for known builtins.
- **OTP 29**: Handles `{ok, Mod, []}` return, reading BEAM files directly from disk.
- **Loader**: Threaded compilation and load results, caching loaded and failed refs. LRU eviction with explicit `code:purge/1`.
- **Module Names**: Maps `DefinitionRef` to `m_<last_8_hex_chars>` (e.g. `'m_e8e52932'`), preventing collisions.

### 4. AST & Language Features (v1.1.0)
- **Guard Clauses**: `Guard` type on `Case` with Erlang `when` clause emission.
- **Holes**: `ast.Hole` variant — `?` parse, compiles to `erlang:error({hole, ...})`.
- **`use` Expression**: `ast.Use` — desugars to lambda-passing: `(use x <- f body)` → `f(fn(x) { body })`.
- **Labeled Arguments**: `(fn* ((x default) ...) body)` — parser/elaborator sugar → curried lambdas.
- **Type Aliases**: `SurfaceTypeAlias` / `SurfacePubTypeAlias` through full elaboration.

### 5. Effects Runtime (`gleamunison_effets.erl`)
Thread-local scope stack managed via process dictionary (`$ability_stack`):
- `push_frame` / `pop_frame` / `find_frame`
- `do_op(AbilityMod, OpIndex, Args, Cont)`: dispatch operation to stack handler.
- `handle_comp({AbilityKey, Handler}, Thunk)`: push handler, run computation, pop handler.

### 5. Pull-based Node Syncing
Advertises local refs, retrieves remote difference, requests missing definition binaries, and persists them via codebase insertions.

### 6. Distributed Topology & Concurrency (Phase 5)
- **Concurrency Primitives**: `spawn`, `send`, `recv`, `self`, `sleep`, `now` — native Erlang process model with content-addressed module dispatch.
- **Remote Ability**: `forkAt`, `await`, `here` — location-transparent distributed compute. `Location` wraps Erlang node names; code shipping via pull-based sync protocol.
- **Mnesia Storage Adapter**: Replicated ACID storage across clustered nodes. Replaces single-node ETS/DETS for multi-node deployments.
- **Supervision Trees**: `gleamunison_sup.erl` — OTP supervisor with isolated link topology. Workers spawned in dedicated processes to prevent cascading termination signals.
- **Serializable Continuations**: Erlang `term_to_binary/1` and `binary_to_term/1` enable cross-node closure serialization. Content-addressed module naming (`m_<hash>`) guarantees identical module versions across nodes.

### 7. Production Operations (v1.1.0)
- **Structured Logging**: `gleamunison/log` — debug/info/warn/error with context dict, ETS-backed.
- **Metrics**: `gleamunison/metrics` — counter/gauge/histogram with `:telemetry` events.
- **Health Checks**: `gleamunison/health` — `/api/health` endpoint, memory/module monitoring.
- **Configuration**: `gleamunison/config` — env/TOML/CLI precedence with typed getters.
- **Trace Inspector**: `gleamunison_trace.erl` — DETS-backed HTTP request capture, SSE push, `/api/traces` endpoint.

### 8. Standard Library (v1.1.0)
- **HTTP Client**: `gleamunison/http_client` — get/post/put/delete, opaque `HttpResponse`.
- **JSON**: `gleamunison/json` — encode/decode wrapping Erlang `json`.
- **DateTime**: `gleamunison/datetime` — opaque `DateTime`, ISO 8601, arithmetic.
- **Filepath**: `gleamunison/filepath` — opaque `Path`, join, parent, extension.
- **Crypto**: `gleamunison/crypto` — SHA256/512, HMAC, random bytes.
- **Template**: `gleamunison/template` — `{{var}}` interpolation with HTML escaping.

## Invariants
- **Type-Inclusive Hash**: The AST term and its inferred type compile to the hash.
- **Append-only Codebase**: Once inserted, definitions never change.
- **Process Isolation**: Ability stack bound to processes.
- **Standalone escript**: zero-dependency ~1.1 MB binary.
- **Content-Addressed Continuations**: Identical hashes guarantee identical module versions across nodes, enabling native Erlang closure serialization.
- **Supervisor Link Isolation**: Supervisor trees spawned in dedicated workers to prevent cascading termination signals.
