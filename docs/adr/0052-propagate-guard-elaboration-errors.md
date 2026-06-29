# ADR-0052: Propagate Case Guard Elaboration Errors

## Context
In `src/gleamunison/elab_term.gleam`, case guard terms were elaborated using `elaborate_term/2`. If guard elaboration failed (due to type mismatches, unbound names, or other semantic issues), the error was caught and swallowed using a default fallback term (`ast.Int(0)`) via `result.unwrap`.

This allowed programs with semantic errors in guards to bypass checks and compile with incorrect fallback behaviors.

## Decision
We decided to propagate case guard elaboration errors through the outer function chain.
- Refactored `elaborate_case/2` to return `Result(#(ElabCtx, Case), ElaborateError)` directly on guard term elaboration via `result.try`.
- Ensured the updated `ElabCtx` is propagated from guard elaboration to downstream stages.
- The downstream `elaborate_cases/3` and `elaborate_term/2` structures were already capable of bubbling up this error type, so no changes to caller signatures or outer patterns were required.

## Consequences
- **Correct Validation**: Case guards are now strictly validated for semantic correctness, and compilation fails early with an `ElaborateError` if a guard contains undefined names or invalid constructs.
- **API and Type Preserved**: The return signatures of all internal elaboration helpers were preserved.
- **Added Testing**: Added `elaborate_guard_error_test` to verify that guard compilation errors are successfully caught and propagated.
