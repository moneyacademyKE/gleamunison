# ADR-0003: Genesis builtins over BuiltinRef

**Status:** Accepted

**Date:** 2026-06-26

## Context

Every runtime needs primitives: `Int.add`, `IO.read_line`, etc. The naive
approach is a special identity type:

```gleam
pub type Reference {
  Ref(Hash)
  BuiltinRef(String)  // second identity system
}
```

This creates a parallel identity space. A `BuiltinRef("Int.add")` and a
`Ref(#some_hash)` are both references, but they use different mechanisms.
The codebase must handle them differently. Verification is different.
Sync is different.

This is a second system — exactly what Hickey warns against.

## Decision

Primitives are defined as AST terms in a genesis block with pre-computed,
well-known hashes. They are seeded into every codebase at creation time.
They use the same `DefinitionRef` type as user code.

The `identity` module has helper functions that return the known refs:

```gleam
pub fn builtin_int_add() -> DefinitionRef { ... }  // known hash from genesis
pub fn builtin_io_read_line() -> DefinitionRef { ... }
```

But these are just convenience functions. The refs themselves are regular
`DefinitionRef(Hash(...))` values.

## Consequences

**Positive:**
- One identity system for everything. A `DefinitionRef` always means the same
  thing, whether it points to `Int.add` or a user's function
- Primitives go through the same pipeline: hash verification, compilation,
  loading, sync
- No special-case code in the codebase, compiler, or loader for "builtins"
- Genesis block is self-verifying: hash each definition, confirm against
  the expected root hash

**Negative:**
- Bootstrap cost: the genesis definitions must be authored as AST terms and
  their hashes pre-computed. This requires a bootstrapping tool
- Primitives cannot be changed without changing their hash (which is correct —
  a different `Int.add` IS a different definition)
- The genesis block must be distributed with the runtime

**Alternative considered:** Native Erlang function references compiled directly
into the runtime. Rejected because it creates a category of things that exist
but have no hash, breaking the content-addressing invariant.
