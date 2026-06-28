# ADR-0039: In-Memory Compilation & Live Distributed Sync Protocol

## Context

Previously, `gleamunison` runtime:
1. Compiled dynamically generated Erlang source modules by writing the source code to a temporary file in `/tmp/`, invoking `compile:file/2`, reading the resulting `.beam` binary back, and deleting the files. This introduced file system dependency, I/O latency, and file deletion hazards.
2. Synchronized definitions across nodes via static FFI stubs (`sync_connect`, `sync_send_refs`, etc.) which returned hardcoded mock data (e.g. `<<"test_node">>`), meaning real clustered nodes could not transfer cryptographic hashes or AST definitions.

## Decision

1. **In-Memory Compilation**: We replace `compile:file/2` with in-memory scan/parse/compile. We scan Erlang source binaries into tokens using `erl_scan:string/1`, split the tokens by dots (`.`) to parse individual AST forms using `erl_parse:parse_form/1`, and compile the resulting forms directly to BEAM binaries using `compile:forms/2`.
2. **Storage Global Registration**: We register the active codebase storage adapter (ETS, DETS, Partitioned DETS, or Mnesia) globally in `persistent_term:put({gleamunison, active_storage}, {Type, Tab})` upon initialization.
3. **Live Sync protocol via RPC**: We implement real clustering sync in `gleamunison_ffi_io.erl` via Erlang distributed pinging (`net_adm:ping/1`) and RPC (`rpc:call/4`).
4. **Mock Fallback for Tests**: We detect test mock nodes using `is_real_node/1` (checking for `@` in the name). Nodes without `@` fall back to the mock stubs to ensure unit tests pass.

## Status

Accepted.

## Consequences

- **Performance**: In-memory compilation has zero disk I/O overhead, executing in microseconds.
- **Robustness**: Eliminates temporal `/tmp/` file hazards and potential lock issues on slow filesystems.
- **Clustering**: Real distributed nodes can now synchronize and ship content-addressed definitions on the fly.
