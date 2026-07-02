# ADR-0061: Phase 13 Hardening and Data-Driven Dogfooding

## Context
As we finalize the production readiness of `gleamunison`, we need to secure the system's FFI boundary, safeguard TCP socket connections, restrict public access to administrative HTTP endpoints, split large source files to comply with the 250 LOC constraint, and optimize the 5600+ auto-generated dogfooding test suite levels to prevent compilation scaling limits.

## Decision
Based on our analysis of safety, performance, and codebase simplicity, we decided on the following:
1. **FFI Serialization Hardening**: Replaced raw Erlang `binary_to_term` deserialization with `binary_to_term(Bin, [safe])` in sync and FFI channels to prevent atom leakage and denial-of-service vectors.
2. **SSE Monitor Swapping**: Replaced process-based socket monitoring with port-based socket monitoring (`erlang:monitor(port, Socket)`) in HTTP routes to correctly detect connection drops when using ranch/cowboy sockets.
3. **HTTP Binding and Restriction**: Configured the HTTP server to only listen on `127.0.0.1` and implemented localhost checking (`is_localhost`) on the `/eval` and `/define` routes to forbid external callers.
4. **Range Utility and Genesis Module Extraction**: Extracted the shared `range` function to `util.gleam`. Extracted the cycle-inducing builtin constants out of `identity.gleam` to `genesis.gleam` and introduced `bootstraps.gleam` to house cycle-free bootstrapping data, ensuring all modules remain strictly `<250 LOC`.
5. **Data-Driven Dogfooding**: Replaced 110+ generated `dogfood_v*.gleam` files (saving 90k+ lines of boilerplate) with a single JSON database file `src/dogfood_data.json` containing level configurations. Implemented a generic VM interpreter in `src/dogfood_runner.gleam` to dynamically run levels loaded via FFI from the JSON database.

## Consequences
- Atom table depletion and remote code execution vulnerabilities are minimized at the serialization boundary.
- Server-Sent Events (SSE) accurately track ranch socket disconnects.
- Large cycle-inducing imports are cleanly untangled.
- Level compilation overhead is reduced from minutes to sub-second load times, with the entire codebase fully adhering to the 250 LOC constraint.
