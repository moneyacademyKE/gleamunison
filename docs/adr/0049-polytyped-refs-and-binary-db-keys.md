# ADR 0049: Poly-typed References and Binary DB Keys

## Status: Implemented (v2.3.1)

## Problem

Gleamunison's sync protocol supports remote network syncing over Erlang RPC (for BEAM nodes) and raw TCP sockets (for non-BEAM/external nodes). During TCP socket sync, nodes exchange content-addressed references.

However, the internal Erlang FFI layer clashed with the database adapters regarding how reference keys are stored:
- Gleam storage adapters compile reference keys to raw `BitArray` (Erlang `binary()`) when calling the FFI database insert/lookup APIs.
- The sync FFI functions (`fetch_defs_binary` and `receive_pushed_defs`) queried and inserted definitions using `{ref, {hash, Bytes}}` tuples as database keys instead of raw binary hashes.
- In `get_local_refs_hex`, the FFI directly read keys from the database, producing a list of raw binaries. It then mapped them using `ref_to_hex`, which only had a clause for `{ref, {hash, Bytes}}` tuples, resulting in a `function_clause` crash that terminated the TCP sync connection process.

## Solution

We unify on storing raw binary hashes as keys across all storage adapters, and make the FFI references poly-typed to handle both formats robustly.

### Key Decisions

1. **Poly-typed `ref_to_hex` conversion**:
   Modify `ref_to_hex` to handle both `{ref, {hash, Bytes}}` tuples and raw binary `Bytes`:
   ```erlang
   ref_to_hex({ref, {hash, Bytes}}) ->
       iolist_to_binary(gleamunison_ffi:hash_to_hex(Bytes));
   ref_to_hex(Bytes) when is_binary(Bytes) ->
       iolist_to_binary(gleamunison_ffi:hash_to_hex(Bytes)).
   ```

2. **Standardize DB Key Representation**:
   Modify `fetch_defs_binary` and `receive_pushed_defs` in `gleamunison_ffi_io.erl` to query and insert entries using raw binary keys (decoded via `hex_to_bytes(Hex)`) rather than `{ref, {hash, Bytes}}` tuples.

## Benefits & Trade-offs

- **Pro**: Fixes the asynchronous TCP connection handler crash.
- **Pro**: Prevents database key pollution (ensures keys in ETS, DETS, and Mnesia are consistently raw binaries).
- **Pro**: Poly-typed hex conversion provides backward and forward compatibility for all parts of the FFI.
- **Con**: Slightly bypasses type checker verification for Erlang FFI boundary types, which is standard for FFI but requires careful test coverage.
