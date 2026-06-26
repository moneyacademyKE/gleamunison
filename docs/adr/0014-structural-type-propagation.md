# ADR 0014: Structural Type Propagation and Lightweight Substitution

## Context
Bug #5 was a stub in type inference returning `TypeVar(0)` for all compound terms. A full Hindley-Milner (HM) unification engine requires extensive state management (unification substitution maps), which conflicts with the `<100 LOC` file limit constraint and increases system complexity.

## Decision
We implemented a structural type propagation model (Option A from the Rich Hickey Gap Analysis) with a lightweight, state-free type substitution helper:
1. Primitive terms directly return their built-in types.
2. Function types and Let structures propagate their child types recursively.
3. Function application (`Apply`) performs a direct substitution of the parameter type variables in the return type using the argument type.

## Consequences
- **Pros**:
  - Extremely simple and state-free (~40 LOC).
  - Robustly resolves polymorphic identity application (`(fun x -> x)(42)`) to `IntType`.
  - Zero performance/memory overhead.
- **Cons**:
  - Does not support full nested multi-variable unification (deferred for future requirements).
