# ADR-0053: Standardize Property Failure Path and FFI Signatures

## Context
In `src/gleamunison_property.erl`, the FFI property check function returned failure maps with atom keys (`counterexample`, `reason`, `passed`). When inspected in Gleam, they leaked as capitalized constructors/atoms (`Counterexample`, `Reason`, `Passed`) rather than strings, violating Gleam's dictionary conventions. Additionally, if the property under test threw an exception, it crashed the VM instead of reporting a clean counterexample failure.

Furthermore, `ffi_prop` in multiple `dogfood_v*.gleam` files was declared with signature `Result(a, b)` instead of `Result(List(a), b)`, causing runtime type mismatch bugs when property checks returned a list of success cases.

## Decision
1. **String Key Representation**:
   - Modified `src/gleamunison_property.erl` to return binary string keys (`<<"counterexample">>`, `<<"reason">>`, `<<"passed">>`).
2. **Exception Safeguard**:
   - Wrapped property execution inside a `try-catch` block in `check_loop/4` to catch any runtime exceptions and report them as standard property failures.
3. **FFI Type Alignment**:
   - Corrected the external signature of `ffi_prop` to return `Result(List(a), b)` across all dogfood modules, and updated dependent helper functions (e.g. `prop_batch/1`) to match.

## Consequences
- **Idiomatic Dictionary**: Property failures are now represented as standard Gleam `Dict(String, Dynamic)` instances.
- **Robust Execution**: VM crashes during failed property assertions are avoided.
- **Strict Type Safety**: Success branches correctly unify as `List(a)` at compile time and runtime.
