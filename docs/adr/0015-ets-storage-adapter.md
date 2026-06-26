# ADR 0015: ETS-Backed Storage Adapter for Codebase Persistence

## Context
The codebase storage adapter design is represented by the `StorageAdapter` record of closures. Since Gleam is a pure functional immutable language, the in-memory adapter previously discarded all data passed to `insert`. 

To maintain clean in-memory persistence without complecting the codebase logic with mutable state threading or heavy OTP actor systems, we need a simple, truly mutable key-value storage.

## Decision
We implement a key-value store using Erlang's ETS (Erlang Term Storage) tables.
- An Erlang FFI module `gleamunison_storage` manages creation, insertion, lookup, and reference listing.
- The `inmemory()` constructor in `storage.gleam` initializes an ETS table and closures capture this reference to perform side-effectful mutations.
- The record signature `StorageAdapter` remains unchanged, preserving full caller compatibility.

## Consequences
- **Pros:** True in-memory codebase persistence is achieved with minimal code. Zero caller-side changes are required.
- **Cons:** Bypasses pure functional constraints, relying on Erlang FFI side-effects (acceptable as storage is naturally stateful).
