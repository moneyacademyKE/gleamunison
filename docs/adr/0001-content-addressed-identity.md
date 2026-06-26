# ADR-0001: Content-addressed identity separation

**Status:** Accepted

**Date:** 2026-06-26

## Context

The system needs to identify code entities (definitions) in a way that is
portable across nodes, verifiable, and independent of naming. Unison uses
content-addressing (hash of serialized AST) as the identity mechanism.

The design challenge is: what should the identity type look like, and what
concerns are complected when identity is conflated with other concepts?

## Decision

Three separate types for three separate concerns:

- `Hash` — opaque, module-private construction, only comparable via
  `hash_equal/2`. Consumers cannot depend on representation.
- `DefinitionRef` — wraps a `Hash`, identifies a definition in the codebase.
  Used for global, content-addressed references.
- `LocalVar` — wraps a de Bruijn index, identifies a local binding within
  a single definition's AST. Used for lexical scope references.

## Consequences

**Positive:**
- No way to confuse a global reference with a local one — they're different
  types, enforced by the compiler
- `DefinitionRef` is the single way to point to a definition. No secondary
  identity via strings, module paths, or names
- `Hash` representation can change (Blake2b, SHA-256, etc.) without affecting
  any consumer outside the `identity` module

**Negative:**
- Extra indirection: two types instead of one for references
- Conversion between `DefinitionRef` and display string requires explicit
  function calls (not a field access)

**Zero-cost:** Both types are single-variant records with no runtime overhead
beyond what the BEAM already pays for tuples.
