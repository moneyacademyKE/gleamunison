# ADR 0016: Three-Phase Pull Sync Protocol

## Context
The previous pull sync protocol sent our own known references directly to `sync_request_defs`, asking the peer node to return files we already possess. This was backwards and did not allow correct state synchronization.

## Decision
We design a correct three-phase pull sync protocol:
1. **Advertise:** Send our set of known hashes to the peer using `sync_send_refs`.
2. **Difference:** Retrieve the set of hashes we are missing (the difference) from the peer using a new FFI call `sync_receive_diff`.
3. **Fetch:** Fetch the definition blobs for only those missing hashes using `sync_request_defs`.
The FFI stubs for these calls are implemented in `gleamunison_ffi.erl` returning safe default empty responses.

## Consequences
- **Pros:** Align pull-sync logic with correct content-addressed distributed sync protocols (matching Unison's codebase sync model).
- **Cons:** Slightly increases the number of network roundtrips, but guarantees correct sync state.
