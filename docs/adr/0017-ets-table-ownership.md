# ADR 0017: ETS Table Ownership and Background Holder Process

## Context
ETS tables in the Erlang VM are owned by the process that creates them. If the owner process terminates, the table is automatically reclaimed by the garbage collector. In our storage adapter, any transient process (such as a unit test runner or a web request handler) calling `storage.inmemory()` would become the table owner. Once that calling process exited, the table was destroyed, causing subsequent lookups or inserts from other processes to crash with `badarg`.

## Decision
We decouple the lifetime of the ETS table from transient worker threads by spawning a dedicated, minimal, unsupervised background holder process inside `gleamunison_storage:new/0`. This holder process creates the ETS table and then enters a recursive message loop (`holder_loop/1`) that does nothing but sleep/wait.

This background holder process acts as the permanent owner of the ETS table. Because the table is created with `public` access, other short-lived processes can perform concurrent reads and writes using the table identifier (TID) passed back by the holder process upon creation.

## Consequences
- **Robustness**: The ETS table and its data survive caller process crashes, which is critical for test isolation and concurrent request execution.
- **Resource Cleanup**: The table remains in memory until the BEAM node shuts down or the holder process is explicitly sent a exit signal (if ever implemented). This is acceptable for our content-addressed codebase.
- **Simplicity**: No complex GenServer setup, supervision trees, or `{'ETS-TRANSFER', ...}` heir handling logic is required.
