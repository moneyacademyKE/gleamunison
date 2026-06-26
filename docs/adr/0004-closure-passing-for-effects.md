# ADR-0004: Closure-passing for effects

**Status:** Accepted

**Date:** 2026-06-26

## Context

Algebraic effects (Unison's "abilities") require a mechanism for:
1. Performing an operation (Do) that dispatches to a dynamically-scoped handler
2. The handler can resume the computation with a result
3. The handler can resume multiple times (multi-shot)
4. Handlers are lexically scoped (Handle establishes the scope)

Three implementation strategies were considered:
1. **Full CPS transformation** — transform the entire program into
   continuation-passing style. Every function receives a continuation.
2. **Interpreter loop** — build a small-step evaluator that handles effects
   explicitly, interpreting effectful terms and compiling pure ones.
3. **Closure-passing at boundaries** — only wrap the Do/Handle boundary with
   closures. Everything else compiles to native BEAM.

## Decision

Use closure-passing at boundaries (option 3). The compiler wraps only the
specific Do and Handle points:

```erlang
%% Do(ability, op, args) compiles to:
Effects:do_(AbilityRef, OpIndex, [Args],
  fun(Result) -> <rest of computation> end)

%% Handle(computation, handler) compiles to:
Effects:handle_(HandlerMap,
  fun() -> <computation body> end)
```

The rest of the program compiles to native BEAM code. No CPS transform. No
interpreter loop.

## Consequences

**Positive:**
- Pure terms (the majority of most programs) compile to native BEAM with zero
  overhead for the effect system
- The BEAM handles everything: closure allocation, GC, capture semantics,
  multi-shot calling
- Continuations are ordinary closures. They can be called 0, 1, or N times
  with no special infrastructure
- Try/catch in `handle_` guarantees stack cleanup on crash

**Negative:**
- Effect boundary has closure allocation cost (but this is proportional to
  the number of Do operations, not the size of the program)
- Requires the compiler to do `contains_effects/1` analysis on each term
  to decide compilation strategy
- Closure capture at Do point must include the full environment — the BEAM
  handles this automatically, but it's worth measuring

**Why not CPS:** CPS transforms the entire program, changing every function's
calling convention. On BEAM, this means every function wraps its result in a
continuation, even when no effects are used. The overhead is constant and
unnecessary for pure code.

**Why not interpreter loop:** An interpreter means effects terms run 10-100x
slower than native BEAM. Worse, the boundary between interpreted and compiled
code is expensive and error-prone.
