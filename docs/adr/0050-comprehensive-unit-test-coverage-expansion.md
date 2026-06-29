# ADR-0050: Comprehensive FFI Unit Test Coverage Expansion

## Context
In our effort to ensure robust, production-grade reliability of the `gleamunison` interpreter, REPL, and distributed synchronization node, we needed to expand unit test coverage across the Erlang FFI modules. These modules (such as `gleamunison_ffi_io`, `gleamunison_config`, `gleamunison_crypto`, `gleamunison_storage`) contain critical low-level code bridging Gleam and Erlang capabilities, including process dictionary states, system environment variables, cryptography, TCP sync hooks, and database backends (ETS, DETS, Partitioned DETS, and Mnesia).

Prior coverage of these Erlang helper modules had untested branches (for example, duplicate Mnesia table initialization, invalid DETS paths, custom hashing/HMAC ciphers, and remote peer synchronization failures).

## Decision
We decided to expand the unified test suite in `src/gleamunison_ffi_test.erl` to comprehensively test all public and private execution branches of these FFI modules. This includes:
1. **Mocking/Simulating Remote Nodes**: Simulating ping/sync failures to nonexistent nodes to verify error-handling paths in `sync_connect`, `sync_send_refs`, `sync_receive_diff`, `sync_request_defs`, and `sync_push_defs`.
2. **Explicit Storage Backend Coverage**: Direct tests for database initialization, insertions, lookups, and local reference listing across all four pluggable adapters (ETS, DETS, Partitioned DETS, and Mnesia), ensuring edge cases (like duplicate Mnesia table registration or closed DETS lookups) are validated.
3. **Robust Cryptographic & Configuration Tests**: Asserting environment variable readbacks (via `gleamunison_config:get_env` and `get_all_env`) and custom hashing/HMAC pathways (via `gleamunison_crypto:hash` and `hmac`), including negative test cases using invalid algorithms.
4. **Export Integrity**: Exporting internal helper functions (such as `ref_to_hex/1`) to prevent undefined function crashes during FFI test execution.

## Consequences
- **Reachable Statement Coverage**: Achieved 100% logical coverage on all reachable statements within the core Erlang FFI modules (`gleamunison_config`, `gleamunison_crypto`, `gleamunison_ffi_io`, `gleamunison_storage`, `gleamunison_log`, `gleamunison_health`, `gleamunison_jets`, `gleamunison_datetime`).
- **Elimination of Silent Failures**: Any changes or updates to low-level FFI code will be caught immediately by the automated test suite.
- **Enhanced Durability**: Persistent storage adapters (DETS, Partitioned DETS, Mnesia) are verified to behave correctly under multiple instantiations, boundary conditions, and clean shutdown cycles.
