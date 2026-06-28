# ADR 0045: Linearity-Enforced Single-Shot Continuations

## Context
1. **Continuation Handling Vulnerability**: Re-entering or resuming a continuation closure multiple times (multi-shot) or dropping it completely (zero-shot) in dynamic stacks leads to difficult-to-debug crashes, memory leaks, and stack pollution.
2. **Koka's Solution**: Koka utilizes compile-time linearity and resource tracking to statically guarantee that continuations are consumed exactly once.
3. **Target Platform Constraint**: The Erlang VM manages runtime stack segments automatically. However, we can guarantee effect safety and clean execution semantics by enforcing linearity constraints at the typechecker/elaboration phase.

## Decision
1. **Continuation Linearity Check**: Propose a static verification pass inside the typechecker (`typecheck.gleam`) or compiler that checks if the continuation parameter `k` is bound and referenced exactly once along every execution branch of an ability operation handler.
2. **Type Error Emit**: If a continuation is duplicated or discarded, raise a compile-time type/linear error (e.g. `LinearityViolation`).

## Consequences
* Completely eliminates a major category of algebraic effect runtime bugs (double-resume or leaked continuation errors).
* Static verification is zero-cost at runtime, maintaining BEAM VM efficiency.
