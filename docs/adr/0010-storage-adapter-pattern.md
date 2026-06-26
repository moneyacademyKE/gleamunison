# ADR-0010: Storage adapter pattern (pluggable backend)

**Status:** Accepted

**Date:** 2026-06-26

## Context

The original `StorageBackend` was a simple enum:

```gleam
pub type StorageBackend {
  InMemory
  DETS
  SQLite
}
```

This was a stub — it declared intent (multiple backends) but didn't define
how backends would be plugged in. The gleamdb gap analysis revealed two
things:

1. **gleamdb (aarondb) is the wrong tool** for our primary storage. Its
   Datalog EAV model is designed for queryable facts, not opaque hash-verified
   blobs. Using it would mean serializing every Definition into EAV triples
   and back — overhead with no benefit.

2. **gleamdb's StorageAdapter pattern is right** — a function-record that
   abstracts the storage interface. We should borrow the pattern but
   parameterize it on our types (BitArray for serialized payloads, not Datom).

## Decision

Replace the `StorageBackend` enum with a `StorageAdapter` function-record:

```gleam
pub type StorageAdapter {
  StorageAdapter(
    insert: fn(DefinitionRef, BitArray) -> Result(Nil, StorageError),
    lookup: fn(DefinitionRef) -> Result(Option(BitArray), StorageError),
    delete: fn(DefinitionRef) -> Result(Nil, StorageError),
    insert_meta: fn(DefinitionRef, BitArray) -> Result(Nil, StorageError),
    lookup_meta: fn(DefinitionRef) -> Result(Option(BitArray), StorageError),
    list_refs: fn() -> Result(List(DefinitionRef), StorageError),
  )
}
```

The adapter operates on **serialized bytes** (`BitArray`), not on `Definition`
or `Datom`. This means:
- The adapter is a dumb byte store — no knowledge of hashes, types, or ASTs
- All semantic invariants (hash verification, duplicate detection) live in
  the `Codebase` layer, not the adapter
- Serialization format is pluggable via a separate `Serializer` function-record

The `Codebase` type wraps an adapter + serializer + in-memory seen set:

```gleam
pub opaque type Codebase {
  Codebase(
    adapter: StorageAdapter,
    serializer: Serializer,
    seen: Map(Hash, DefinitionRef),
  )
}
```

## Consequences

**Positive:**
- **Clean separation of concerns**: adapter moves bytes, codebase enforces
  invariants, serializer handles format
- **Borrows the right pattern from gleamdb** without the wrong data model
- **Any backend** can be used by implementing 6 functions (inmemory, DETS,
  Mnesia, filesystem, S3, etc.)
- **Serialization format** can change independently of storage (swap JSON for
  Erlang term-to-binary without touching the adapter)
- **The seen set** is always in memory for fast dedup checks, regardless of
  the storage backend's latency

**Negative:**
- **Two levels of indirection**: adapter + serializer for every read/write
  (acceptable — the BEAM optimizes function records well)
- **Serialization overhead**: every Definition is serialized on write and
  deserialized on read (necessary for any non-in-memory backend)
- **The seen set must fit in memory**: for a prototype this is fine; for
  production with millions of definitions, it would need an ETS-backed
  seen set instead of a Dict

**Adapter factories provided:**
- `inmemory()` — prototype, uses Gleam Dict
- `dets(path)` — single-node durable, uses Erlang dets FFI
- `mnesia(nodes)` — distributed, uses Mnesia

**Not provided:**
- libsql/SQLite backend — not needed for prototype. Could be added later
  by implementing the 6-function interface.
- gleamdb adapter — would be an adapter that wraps gleamdb's Mnesia/Raft
  backends but stores Blobs (not EAV facts). Possible but not prioritized.
