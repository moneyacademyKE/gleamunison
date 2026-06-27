# Gleamunison Architecture

## Overview
gleamunison is a content-addressed language runtime with algebraic effects running on the Erlang BEAM, implemented in Gleam.
1. **Content-addressed code**: identity = SHA256 hash of serialized AST.
2. **Algebraic effects**: dynamic scope dispatch with resumable continuations via process dictionary.
3. **BEAM runtime**: hot code swapping, process isolation, and OTP 29 compatibility.

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
The hash IS the identity. Uses Erlang's built-in crypto module to generate 256-bit OpenSSL-backed SHA256 hashes. Genesis stubs are padded to the 256-bit boundary (`<<1:256>>`).

### 2. Codebase Storage
Pluggable storage adapter supporting:
- `inmemory()`: volatile ETS-backed storage.
- `dets(path)`: durable disk-based storage with clean `close` and `dets_delete_file` controls.

### 3. Compilation & Loading
- **Compiler**: `emit_term` concatenates Erlang source code from AST, invoking `compile:file/2`.
- **OTP 29**: Handles `{ok, Mod, []}` return, reading BEAM files directly from disk.
- **Loader**: Threaded compilation and load results, caching loaded and failed refs.
- **Module Names**: Maps `DefinitionRef` to `m_<last_8_hex_chars>` (e.g. `'m_e8e52932'`), preventing collisions.


### 4. Effects Runtime (`gleamunison_effets.erl`)
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

## Invariants
- **Type-Inclusive Hash**: The AST term and its inferred type compile to the hash.
- **Append-only Codebase**: Once inserted, definitions never change.
- **Process Isolation**: Ability stack bound to processes.
- **Standalone escript**: zero-dependency ~1.1 MB binary.
- **Content-Addressed Continuations**: Identical hashes guarantee identical module versions across nodes, enabling native Erlang closure serialization.
- **Supervisor Link Isolation**: Supervisor trees spawned in dedicated workers to prevent cascading termination signals.
