# ADR-0008: Process dictionary for dynamic scope stack

**Status:** Accepted

**Date:** 2026-06-26

## Context

The effects system requires a dynamic scope stack: `Handle` pushes an ability
handler, the computation sees it, and `Handle` pops it afterward. The
alternative to dynamic scope is threading the handler stack through every
function call as an explicit parameter (static threading).

Static threading requires changing every function's signature to accept the
handler stack. This is CPS-lite — it works but adds overhead to every call,
even when no effects are used.

## Decision

Use the BEAM process dictionary (`erlang:put/2`, `erlang:get/1`) for the
dynamic scope stack. The key `'$ability_stack'` holds a list of handler frames.

The `effects.gleam` module provides the FFI with safety guarantees:

```gleam
pub fn handle_(handler_map, computation_thunk) -> Dynamic {
  // 1. Push handler onto the process dictionary stack
  // 2. Try: call computation_thunk()
  // 3. Catch: pop handler, re-raise
  // 4. Pop handler
  // 5. Return
}
```

## Consequences

**Positive:**
- Zero overhead for pure code: no stack threading, no handler parameters on
  any function
- Process isolation: the stack is per-process. Two processes evaluating the
  same Handle do not interfere
- No type changes: pure functions and effectful functions use the same calling
  convention
- Handle cleanup is guaranteed by try/catch — the stack invariant is maintained
  even on crash

**Negative:**
- Process dictionary is mutable state. Bugs in the `handle_` implementation
  can corrupt the stack (but this is prevented by the try/catch guarantee)
- Not inspectable from outside the process (cannot ask "what handlers are in
  scope for process P?")
- The process dictionary is a global per-process namespace — the
  `'$ability_stack'` key could theoretically collide with something else
  (mitigation: `$` prefix is a naming convention for internal keys)

**Why not static threading:** Changes every function signature, adds allocation
overhead for the stack on every call, and complects effect handling with every
function's type. The BEAM's process dictionary was designed for exactly this
kind of per-process context, and we trust it within the try/catch guard.
