# ADR 0042: Supervised ETS Table Ownership for Peer Sync

## Context
1. **Transient Table Ownership Regression**: In `gleamunison_ffi_io.erl`, the `register_peer_refs/2` function was creating the named ETS table `gleamunison_peer_refs` dynamically on demand. Because this function is invoked inside transient RPC connections (which exit immediately after execution), the table was garbage-collected and destroyed upon function exit.
2. **Consequences of Regression**: Subsequent calls to `compute_diff/1` either crashed with `badarg` or always returned empty lists because they could not read the deleted table. This broke the pull-based peer synchronization logic.

## Decision
1. **Supervised Initialization**: Initialize the `gleamunison_peer_refs` public named table inside the long-lived, supervisor-backed `ets_holder` worker process in `gleamunison_sup.erl`.
2. **Ephemeral Simplification**: Simplify `register_peer_refs/2` in `gleamunison_ffi_io.erl` to only insert records. It will rely on the table created by the persistent background process, ensuring data persists across RPC lifecycles.

## Consequences
* Peer sync state is persisted reliably across RPC requests.
* Aligns with the core ETS table ownership patterns specified in ADR-0017.
