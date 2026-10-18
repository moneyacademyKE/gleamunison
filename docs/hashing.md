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

## Storage and peer admission

Definition identity and wire bytes have separate jobs. Definitions are stored
in a versioned `GUDEF` envelope containing bounded, uncompressed external-term
data. `definition_codec.decode` validates its shape and canonical encoding;
`storage.verify_content` recomputes the structural hash before admission.
Source spans are omitted and requirement rows are canonical sets. Ordinary
blobs still use their byte hash; prompts retain the `promptdef:` hash domain.

Use `storage.insert_content` or `codebase.insert_raw_checked` for immutable
content, and `storage.check_content` to detect corruption at a known immutable
ref. Raw adapter writes remain trusted key/value operations because mutable
branch pointers are not content-addressed bytes. Peer admission never exempts
pointer-shaped payloads from verification.

## Identity and payload compatibility

Function requirements are part of type identity. `Unique` declarations bind
both the nominal GUID and the full parameter/constructor schema, preventing a
schema from being substituted under the same reference. Empty requirement
rows preserve existing pure-function hashes; effectful and unique definitions
and their transitive dependents need rebuilding after this change.

Legacy inspect-rendered definition payloads cannot be decoded and re-hashed.
Back up the old store and rebuild these entries from trusted source into a
fresh store; do not accept unverifiable legacy payloads from peers. Existing
byte-hashed blob formats are unchanged. See [ADR 0065](adr/0065-verified-cas-admission.md)
for limits, alternatives, and the distinction between integrity and trust.
