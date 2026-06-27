# ADR 0026: Canonical Binary Serialization for Hash Invariants

## Context
1. **Fallback Inspect Hashing**: Previously, `codebase.gleam` used `string.inspect(other)` as a fallback for hashing term and type variants that weren't fully structured (e.g. `Match`, `Do`, `Handle`, `LocalVarRef`, `RefTo`, `TypeDef`, `AbilityDecl`).
2. **Identity Invariant Threat**: Gleam's `string.inspect` output is not guaranteed to be stable across compiler versions, build targets, or platform implementations. This breaks the content-addressed invariant: a definition's hash must depend only on its pure structural content.
3. **Collisions on Type Declarations**: The previous hashing ignored constructor arguments in type declarations and operation inputs/outputs in ability declarations, causing definitions with different types to collide on the same hash.

## Decision
1. **Remove string.inspect Fallbacks**: Replace all `string.inspect` fallbacks in `hash_term`, `hash_type`, and `hash_of_definition` with fully structured, canonical recursive binary serializations.
2. **Structured Component Hashing**: 
   - Hashing pattern and case components for `Match` terms.
   - Hashing type references, constructor structures, and operation inputs/outputs recursively.
3. **CAS Idempotent Insert**: Change `DuplicateDef` behavior on duplicate insert. Since content-addressing is idempotent, inserting a definition with an already-present hash should return `Ok(codebase)` instead of an `Error`.

## Consequences
- Guarantees fully deterministic content-addressing across compiler and target platforms.
- Eliminates hash collisions for different type and ability signatures.
- Correctly aligns codebase insert behavior with semantic CAS store patterns.
