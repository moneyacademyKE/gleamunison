# Dogfooding Playbook — Levels 1551–1600

Comprehensive unit test coverage expansion across Erlang FFI modules. These verification levels ensure complete logical coverage for dynamic environment lookups, database storage backends, cryptographic utilities, network peer synchronization, process dictionary scopes, and standalone execution.

All levels are verified by running `gleam test` and `bb scripts/run_coverage.clj`.

---

## Level 1551–1560: FFI Coverage Certification

**Level 1551** — FFI Config Lookup Coverage (`gleamunison_config:get_env` & `get_all_env`).
- **Expected:** Verifies environment variable readback paths, including missing keys and listing all active system variables.

**Level 1552** — FFI Cryptography Algorithm & Hashing Coverage (`gleamunison_crypto:hash` & `hmac`).
- **Expected:** Verifies cryptographic hash generation (SHA256, SHA512, MD5), HMAC ciphers, random byte generators, and failure catch blocks.

**Level 1553** **(Recommended)** — FFI Storage Adapter DETS Initialization Coverage (`gleamunison_storage:dets_new`).
- **Expected:** Verifies DETS table creation paths, including error-handling recovery when trying to open invalid paths.

**Level 1554** — FFI Storage Adapter Mnesia Duplicate Creation Coverage (`gleamunison_storage:mnesia_new`).
- **Expected:** Verifies Mnesia table creation paths, including the duplicate table name fallback branch (`already_exists`).

**Level 1555** — FFI Peer Network Connection Coverage (`gleamunison_ffi_io:sync_connect`).
- **Expected:** Verifies TCP connections to offline nodes, asserting correct propagation of connection failures.

**Level 1556** — FFI Peer Reference Listing Coverage (`gleamunison_ffi_io:sync_send_refs`).
- **Expected:** Verifies peer sync messaging errors when transferring refs to nonexistent remote topology endpoints.

**Level 1557** — FFI Peer Diff Receiving Coverage (`gleamunison_ffi_io:sync_receive_diff`).
- **Expected:** Verifies remote call errors when requesting diff packages from unreachable sync sources.

**Level 1558** — FFI Peer Definition Fetching Coverage (`gleamunison_ffi_io:sync_request_defs`).
- **Expected:** Verifies failure reporting path when sending requests for definitions to offline node targets.

**Level 1559** — FFI Peer Definition Pushing Coverage (`gleamunison_ffi_io:sync_push_defs`).
- **Expected:** Verifies remote call errors when pushing compiled binary definitions to an unreachable receiver.

**Level 1560** — v2.5 FFI Conformance Certification: 571 dogfood levels, 52 unit tests, 623 total conformance validations across 15 playbook files.
- **Expected:** All tests pass synchronously; logical statement coverage for core FFI modules exceeds 90%.
