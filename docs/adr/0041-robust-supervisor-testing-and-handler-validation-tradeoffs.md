# ADR 0041: Robust Supervisor Testing & Handler Validation Tradeoffs

## Context
1. **Flaky Supervisor Testing**: The existing `test_supervisor_restart/0` in `gleamunison_sup.erl` uses a hardcoded `timer:sleep(50)` delay to wait for the supervisor to restart the crashed `gleamunison_ets_holder` worker process. Under CPU contention or parallel test execution, this timing assumption often fails, leading to false-positive test suite failures (e.g. `badmatch` on `is_pid(Pid2)` when it returns `undefined`).
2. **Compile-time Handler Validation**: A gap analysis shows that `ast.Handle` terms are not checked for completeness or arity during compilation/typechecking, even though a `validate_handler/3` function exists in `types.gleam`. This is a conscious runtime tradeoff to allow dynamic / anonymous handler closures.

## Decision
1. **Robust Polling for Restarts**: Implement a recursive helper `wait_for_restart/2` in `gleamunison_sup.erl` that polls `whereis` up to 100 times (10ms sleep between checks) to wait for the restarted PID. This replaces the fragile 50ms sleep and guarantees reliability.
2. **Accept Compile-time Handler Tradeoff**: Retain `validate_handler/3` as an on-demand validation utility and unit testing construct. Document the tradeoff: since handlers in surface Lisp syntax are represented as anonymous lambdas or dynamically resolved function references, enforcing compile-time exhaustiveness checks on AST-level handler terms would break dynamic handlers. Runtime FFI stack guards remain the primary safety mechanism.

## Consequences
* Test suite execution is highly robust and flake-free.
* The compiler retains the flexibility to support both static and dynamic handler closures.
