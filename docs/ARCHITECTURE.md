# Gleamunison Architecture

## Overview

gleamunison is a running prototype of a content-addressed, algebraically-effected
programming language on the Erlang BEAM. It combines three ideas:

1. **Unison's content-addressed code** — code identity = hash of serialized AST
2. **Algebraic effects** (like Unison's abilities) — dynamic dispatch with
   resumable continuations via process dictionary
3. **BEAM as runtime** — hot code swapping, process isolation, OTP 29 compatibility

## Pipeline (implemented)

```
┌──────────┐    ┌────────────┐    ┌──────────┐    ┌──────────┐
│ Gleam    │───▶│ Elaborate  │───▶│ Core AST │───▶│ Hash     │
│ Surface  │    │ (2-phase)  │    │          │    │ (phash2) │
│ Types    │    │ name +     │    │ Term     │    └────┬─────┘
└──────────┘    │ ability    │    │ Def      │         │
                │ resolution │    │ Unit     │         │
                │ de Bruijn  │    └────┬─────┘         │
                │ assignment │         │               │
                └────────────┘         ▼               ▼
                                  ┌──────────┐    ┌──────────┐
                                  │ Type     │    │ Codebase │
                                  │ Check    │    │ (in-mem) │
                                  │          │    │ dedup    │
                                  │ infer    │    │ by hash  │
                                  │ Int/Float│    └────┬─────┘
                                  │ Text/List │        │
                                  └──────────┘         ▼
                                                  ┌──────────┐
                                                  │ Compiler │
                                                  │          │
                                                  │ Term →   │
                                                  │ Erlang   │
                                                  │ source → │
                                                  │ compile  │
                                                  │ :file/2  │
                                                  │ (OTP 29) │
                                                  └────┬─────┘
                                                       │
                                                       ▼
                                                  ┌──────────┐
                                                  │ Loader   │
                                                  │          │
                                                  │ ensure   │
                                                  │ _loaded  │
                                                  │ → code:  │
                                                  │ load_bin │
                                                  │ ary/3    │
                                                  └────┬─────┘
                                                       │
                                                       ▼
                                                  ┌──────────┐
                                                  │ Runtime  │
                                                  │          │
                                                  │ $eval()  │
                                                  │ call     │
                                                  │ via BEAM │
                                                  └──────────┘
```

## Data flow

### Identity

```
Core AST → Serialize → phash2 → Hash(32-bit) → DefinitionRef
```

A `DefinitionRef` is just a `Hash`. No name, no version. The hash IS the
identity. Currently uses `erlang:phash2/1` (32-bit, fast, prototype quality).
Can be swapped to Blake2b for production without changing the type system.

### Storage

```
Codebase(in-memory):
  seen: Dict(Hash, DefinitionRef)   — dedup cache
  adapter: StorageAdapter            — pluggable backend (inmemory, DETS, Mnesia)

StorageAdapter:
  insert(DefinitionRef, BitArray) -> Result(Nil, Error)
  lookup(DefinitionRef) -> Result(Option(BitArray), Error)
  list_refs() -> Result(List(DefinitionRef), Error)
```

### Compilation

```
Definition(TermDef or TypeDef or AbilityDecl)
  → Erlang source code (emit_term handles all 7 Term variants)
  → compile:file/2 with {outdir, return} options
  → In OTP 29, returns {ok, Mod, []} — read beam from file
  → BEAM binary returned to caller
```

### Loading

```
Loader.compiler: Compiler
Loader.loaded: Set(DefinitionRef)   — known good
Loader.failed: Dict(DefinitionRef, LoaderError)  — known bad

ensure_loaded(loader, ref, def)
  1. Check loaded set → skip if done
  2. Check failed set → return cached error
  3. compile_definition → BEAM binary. Thread CompileFailed details on failure and store in failed dictionary.
  4. load_binary (FFI) → code:load_binary/3. Thread LoadFailed details on failure and store in failed dictionary.
  5. Update loaded set on success
```

### Module naming

Each compiled definition becomes a BEAM module named `m_<last_8_hex_chars>`.
The `m_` prefix prevents collision with user source code (no Gleam module
name starts with `m_` followed by hex characters).

Module names are valid Erlang atoms: `'m_04cc725a'`.

## Effects model

The `gleamunison_effets.erl` runtime module manages a per-process dynamic
scope stack stored in the process dictionary under `$ability_stack`:

```
Stack = [{AbilityModule, OpDict} | ...]
```

- `push_frame(AbilityMod)` — discovers `op_N/2` exports, pushes handler frame
- `pop_frame()` — removes top frame
- `find_frame(AbilityMod)` — walks stack, returns matching frame
- `do_op(AbilityMod, OpIndex, Args, Cont)` — looks up frame, calls handler
- `handle_comp({AbilityKey, Handler}, Thunk)` — push, run, pop

## Sync model

Pull-based: "Here's what I have, tell me what you need."
- `SyncState` tracks peer connections and known refs
- `PeerState` tracks last_seen, refs, status per peer
- `pull_sync()` connects to peer, exchanges refs
- Erlang distribution FFI stubs: `sync_connect`, `sync_send_refs`, etc.

## OTP 29 considerations

- `compile:file/2` with `return` option returns `{ok, Mod, []}` — the empty
  list in the third position means "binary on disk, not returned in memory".
  Must read the `.beam` file from the output directory.
- `code:load_binary/3` is fully supported — guards on `is_atom(Mod)`,
  `is_list(File)`, `is_binary(Binary)`.
- `erlang:type/1` was removed — use `is_binary/1`, `is_list/1`, etc.
- Gleam v1.0+ represents `String` as UTF-8 binary — all FFI receives binaries.

## Key invariants

- **Hash includes inferred type** — `TermDef(term, typ)` both contribute to hash
- **Append-only codebase** — once inserted, a definition never changes
- **Hash verification on insert** — corrupted data is rejected
- **Process-isolated effects** — dynamic scope stack in process dictionary
- **Module name isolation** — `m_` prefix prevents VM-level collisions
- **escript standalone** — 281KB binary, no Gleam dependency at runtime
