# Hashing: structural identity in gleamunison

How definitions get their content address, and what that buys us.

## The scheme

`codebase.hash_of_definition` hashes the **elaborated** core term
(`ast.Term`), never surface syntax:

1. **Elaboration erases names.** Surface binders become de Bruijn
   indices (`LocalVar = Local(index)`), assigned by a flat counter in
   `elab_ctx` (`add_binding`). Each definition elaborates with a fresh
   binding scope (`elab_term_def` discards the returned context), so
   indices depend only on the term's own structure — never on the unit,
   the order of elaboration, or the source spelling of names.
2. **Serialization is canonical.** `hash_term`/`hash_type`/
   `hash_pattern` build a tagged bytewise encoding
   (`"lam:" <> index <> body`, `"int:" <> n`, …) — not
   `string.inspect` of the AST. SHA-256 over those bytes is the
   definition's identity.

## What this guarantees

- **Alpha-invariance**: `fn x -> x` and `fn y -> y` are the same
  definition. Proven by `test/alpha_hash_test.gleam`
  (renamed binders, nested binders, and shadowing all hash
  identically; different bodies hash differently).
- **Referential transparency of identity**: a hash depends only on the
  term's structure and the (recursive) hashes of its references.
- **Per-definition determinism**: a definition's hash is independent
  of what else is in the file or unit.

## What this enables downstream

Everything content-addressed inherits these properties: the Merkle-DAG
store, `patch` propagation, `evidence` attestations, and `sync`
conflict detection all key on this hash.

## Known boundary

`Unique` type declarations carry a caller-supplied GUID, so their
identity is nominal by design. All term definitions are structural.
