# ADR-0031: Modular FFI Decomposition for Strict Compliance

## Status
Accepted

## Context
Our project guidelines enforce a strict limit of 250 lines of code (LOC) per file to ensure high cohesion and modular design. The main FFI wrapper, `gleamunison_ffi.erl`, grew to 204 LOC. Adding new FFI bindings for distributed systems or additional builtins would inevitably violate the LOC boundary.

## Decision
We split the responsibilities of `gleamunison_ffi.erl` into two specialized modules:
1. `gleamunison_ffi.erl` (141 LOC): Houses core cryptographic hashing, source compilation, code-loading, purging, and standalone packaging utilities.
2. `gleamunison_ffi_io.erl` (69 LOC): Houses transient process evaluation, process dictionary state variables, and node-synchronization mock interfaces.

Corresponding Gleam files (`sync_types.gleam` and `dogfood_core.gleam`) were updated to direct their external Erlang calls to the appropriate FFI module.

## Consequences
- Strict compliance with the <250 LOC rule is preserved.
- Code readability is improved through clear division of compile-time and run-time IO concerns.
- FFI expansion can proceed safely under separate namespaces.
