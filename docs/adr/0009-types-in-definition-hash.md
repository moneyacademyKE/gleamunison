# ADR-0009: Types are part of definition identity

**Status:** Accepted

**Date:** 2026-06-26

**Supersedes:** ADR-0002 (amended)

## Context

ADR-0002 established that types should be computed metadata, stored
separately from definitions, and NOT part of the hash. This was motivated
by the correct observation that type *annotations* shouldn't change hashes.

However, analysis of Unison's actual architecture revealed that the
*inferred type* IS part of the hash. The reasoning:

1. **Runtime semantics depend on type.** In a language with overloaded
   operators or type-directed dispatch, `x + 1` behaves differently depending
   on whether `x` is `Nat` or `Int`. The type determines which `+` is called.

2. **The type is the public interface.** Changing a function's type signature
   IS a different definition. A function `foo : Nat -> Int` is different from
   `foo : Nat -> Nat`, even if the body is structurally identical.

3. **Unison does it.** "A hash in Unison is a 512-bit SHA3 digest of a term
   or a type's internal structure, excluding all names." The internal
   structure includes the inferred type.

## Decision

The `TermDef` variant of `Definition` includes a `typ: Type` field. The hash
of a `TermDef` is computed from both the serialized term AND the serialized
type:

```
hash(TermDef(term, typ)) = Blake2b(canonical(term) ++ canonical(typ))
```

The pipeline changes from:
```
Elaborate → Hash → Codebase → Type Check (after)
```
To:
```
Elaborate → Type Check → Hash → Codebase (before)
```

## Consequences

**Positive:**
- Two terms with the same structure but different types have different hashes,
  matching Unison's behavior
- The type is automatically propagated through the Merkle DAG — a Unit
  containing typed definitions carries the type information with it
- TypeCache is still used for fast lookup but is no longer the sole
  authority on type identity
- Type *annotations* in surface syntax still don't affect the hash —
  they elaborate to the inferred type during type checking, and the inferred
  type is what gets hashed

**Negative:**
- The pipeline is more constrained: type checking must complete before
  hashing. This adds a dependency in the compilation order.
- `Definition.TermDef` requires a `Type` value, which requires the entire
  type system to be available when constructing definitions
- Two-phase elaboration: first produce untyped ASTs, then type check, then
  construct the final Definitions with types filled in

**Key invariant preserved:** Individual `Term` nodes within a definition
still don't carry type annotations. Types are only attached at the
`Definition` boundary. This means sub-term hashing (if we ever need it)
only sees structural content, not types.
