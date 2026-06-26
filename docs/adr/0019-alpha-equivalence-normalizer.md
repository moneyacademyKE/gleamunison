# ADR 0019: Alpha-Equivalence Normalization for Polymorphic Types

## Context
When typechecking content-addressed definitions in GleamUnison, types contain free type variables (e.g. `TypeVar(index)`). If different definitions use different variable indices (e.g. `TypeVar(0)` vs `TypeVar(1)`), structural equality check `inferred == typ` fails even though the types are semantically identical (alpha-equivalent).

## Decision
Implement a sequential type variable index normalizer (`normalize_type`) in `typecheck.gleam`. This normalizer renames type variables sequentially starting at 0 as they are encountered in a depth-first traversal of the type structure. Type equality is then checked on the normalized representations.

## Consequences
- Checks for polymorphic type equivalence are robust and immune to variable renaming.
- Eliminates false negatives in definition typechecking.
- Negligible performance overhead.
