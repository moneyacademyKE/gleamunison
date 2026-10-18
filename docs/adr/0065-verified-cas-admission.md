# ADR 0065: Verified CAS admission and recoverable definition payloads

- **Status:** Accepted
- **Date:** 2026-10-19 (EAT)
- **Tracking:** `bk-7eeb`
- **Related:** [ADR 0009](0009-types-in-definition-hash.md), [ADR 0010](0010-storage-adapter-pattern.md), [ADR 0026](0026-canonical-hash-serialization.md)

## Context

Structural identity and stored bytes were different things. `hash_of_definition` already used tagged structural hashes, but insertion persisted `string.inspect(def)`, which could not be decoded and re-hashed. Both typed sync and the Erlang push receiver trusted the first payload for an unknown reference. Codebase insertion discarded storage errors. Function requirements and unique declaration schemas were not included in identity.

Storage adapters also hold mutable branch-pointer cells. Making every adapter write a byte-hash check would break that legitimate contract, while implicitly exempting pointer-shaped remote data would grant untrusted mutation authority.

## Decision

1. Keep storage adapters as **trusted key/value primitives**. Compose them with `storage.insert_content` for immutable admission. Expose `verify_content` and `check_content` for explicit integrity checks. These functions do not grant mutation authority for branch pointers.
2. Persist definitions as `GUDEF` + format version 1 + uncompressed Erlang external-term data, using minor version 2. Decode with `safe` and `used`, require complete consumption and canonical re-encoding, validate every AST family, and reject unexpected terms. Never execute the decoded value.
3. Limit an individual payload to 1 MiB, an AST to 20,000 visited values and depth 96, and a pushed batch to 4,096 entries. Reject compressed ETF before expansion. Reject trailing bytes in both definition payloads and TCP messages. The TCP frame already has a 1 MiB cap.
4. Strip source spans from wire data and canonicalize requirement rows as sets. Recompute the existing structural definition hash after decoding; do not substitute a hash of the ETF bytes.
5. Retain the existing raw-blob and `promptdef:` hash domains. Unknown/unverifiable first writes fail closed. Preserve the first admitted byte binding; report lookup/insert errors rather than treating them as absence or success.
6. Bind function requirements into type hashes and bind unique declarations to their GUID **and** full schema. Empty requirement rows preserve previous pure function hashes. Nominal GUIDs remain distinguishing input, not permission to alter a schema under one reference.
7. Use `insert_raw_checked` in fallible paths. Keep the old `insert_raw` return shape as a compatibility wrapper: failure leaves the codebase unchanged. New code must not use that wrapper when it needs error information. Eliminate the redundant `seen` cache so admission always observes the adapter.
8. Pre-validate complete pushed batches and existing bindings before writes; propagate failure through TCP and distributed-Erlang responses. DETS insert/close must report sync errors. Partition opens/closes must not silently record success after failure.

## Consequences

- A forged first write, conflicting replacement, malformed definition, or failed store cannot masquerade as successful admission.
- The format is a BEAM payload format, not a language-independent public interchange standard. Structural identity remains separate from this runtime encoding.
- **Compatibility change:** old inspect-rendered definitions cannot be securely re-hashed. Rebuild those entries from trusted source into a fresh store; do not silently accept them from peers. Back up the old store first. Existing content-addressed blob formats remain unchanged.
- **Identity change:** effectful function types and unique declarations receive new references. Their transitive dependents must be rebuilt and packages republished. Do not mix old and new references by rewriting pointers blindly.
- `check_content` is non-destructive detection, not automatic repair. Pass immutable refs only; branch-pointer cells are deliberately outside that contract.
- Validation is not sandboxing or provenance. Valid code still needs capability/evidence policy before execution. Peers still need transport/authentication policy.
- DETS sync acknowledges the storage operation; it does not create a multi-record crash transaction or a backup/restore protocol. Validation failures land no batch entries, but an I/O failure during a multi-entry batch may leave an admitted prefix.
- The trusted low-level adapter can deliberately overwrite a key. Its callers are inside the trust boundary. No claim of transactional compare-and-swap across competing trusted writers is made.

## Alternatives considered

- **Hash the display string:** rejected; output is not a stable or recoverable definition format.
- **Hash ETF bytes as definition identity:** rejected; would discard established structural/alpha identity and make metadata or runtime encoding identity-bearing.
- **Validate all adapter writes identically:** rejected; mutable branch pointers are a different contract.
- **Trust first write and only pin subsequent bytes:** rejected; the first malicious sender wins.
- **Add a database or serializer framework:** rejected; the existing hash function, adapters, and bounded FFI codec compose without dependencies.

## Verification / follow-up

Run `PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH gleam test` and `gleam format --check` with the same PATH. Regression suites: `cas_admission_test`, `definition_codec_test`, and `cas_tcp_test`. They exercise actual adapters and a real loopback TCP listener, including forged first writes, shape/depth/size violations, effect/schema identity, corruption detection, persistence reopen, and failure propagation.

The explicit full gate reported **385 passed, no failures** before documentation changes. Release proof must additionally build the escript and exercise its content-addressed dogfood case. This ADR does not claim a Hex publication, TLS transport, signed evidence, or production readiness.
