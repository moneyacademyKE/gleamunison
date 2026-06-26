# ADR 0020: DETS Persistent Storage, SHA256 Hashing, and S-Expression Parser

## Context
The Gleamunison prototype originally utilized a volatile, non-durable in-memory ETS table for storage, a non-cryptographic 32-bit `erlang:phash2` hash for content identity (which is prone to collisions), and direct AST construction instead of a user-facing surface language syntax. To transition to a production-grade system, we require persistent storage, secure/deterministic cryptographic identities, and a text-based parser.

## Decision
1. **DETS Storage Adapter**: Implement a disk-based storage adapter utilizing Erlang's native `dets` library. Equipt the `StorageAdapter` type with a `close` function to allow clean file release and prevent slow table repair cycles on dirty start.
2. **SHA256 Cryptographic Identity**: Replace `erlang:phash2` with `crypto:hash(sha256, Bytes)` via Erlang's built-in `crypto` module, and adjust genesis built-ins to use 256-bit hashes.
3. **S-Expression Surface Parser**: Implement a lightweight S-expression lexical tokenizer and recursive-descent parser directly in `parser.gleam` to process text code.
4. **Lifecycle Control**: Expose `dets_delete_file` to support file cleanups in testing environments, avoiding state leakage between test runs.

## Consequences
- Definitions survive application restarts and are stored directly on the file system in native Erlang format.
- Code identity is secure against hash collision vulnerabilities.
- S-expression syntax provides an accessible text entry point for the compiler.
- Explicit resource management (`close`/`delete_file`) guarantees test purity.
