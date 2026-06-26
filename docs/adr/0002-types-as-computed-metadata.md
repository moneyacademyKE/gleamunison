# ADR-0002: Types as part of definition identity (amended)

**Status:** Amended by ADR-0009

**Date:** 2026-06-26

**Amendment date:** 2026-06-26

## Original decision

Types should NOT be on Term constructors. Type annotations should not affect
hashes. Types are computed after hashing and stored in a separate TypeCache.

## Why the amendment

The original decision conflated two different things:
1. **Type annotations** on surface syntax — should NOT change the hash (correct)
2. **The inferred type** of the definition — SHOULD change the hash (incorrectly excluded)

In Unison, the hash includes the type. This is correct because the type affects
runtime behavior. Two terms with the same AST but different types have different
runtime semantics (e.g., via overloaded operators or type-directed dispatch).

The error was: "Types are derivable from structure" — this is true, but the
*derivation* is the type of the STRUCTURE IN CONTEXT, not the structure alone.
The same AST `x + 1` has different meaning if `x : Nat` vs `x : Int` because
the `+` operator dispatches to different implementations.

## What's still correct

- **No Type fields on Term constructors.** Individual AST nodes within a
  definition don't carry type annotations. This is still right.
- **TypeCache is still useful** as a fast lookup index, but it's no longer
  the source of truth for type identity.

## What changed

- The `Definition.TermDef` record now includes a `typ: Type` field
- The hash includes both term and type
- The pipeline: Elaborate → **Type Check** → Hash → Codebase
  (type checking now runs BEFORE hashing, not after)
