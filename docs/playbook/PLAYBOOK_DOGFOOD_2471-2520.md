# Playbook Dogfood Batch 27 — Loader Deeper, Storage Adapters, Elaborate Depth, Cross-Module Runtime

## Levels 2471–2520

### Theme

Loader depth (limits, eviction, idempotent loads), all 4 storage adapters (inmemory, DETS, partitioned, mnesia),
elaborate depth (abilities, cross-ref defs, complex expressions), REPL+serialization depth,
cross-module all value types executed at runtime, parser+type edge cases.

### Levels

- 2471-2476: Loader depth — limit 3+5 defs, 10 same loads, interleaved, is_loaded alternates,
  TypeDef+TermDef, reload after eviction
- 2477-2482: Storage adapters — inmemory 50/200 refs, DETS, partitioned, mnesia, cross-adapter
- 2483-2490: Elaborate depth — ability+term, cross-ref defs, lambda, nested add, bool, complex let,
  float list, identity Apply
- 2491-2498: REPL+serialize — var ref, redefine, 4-def chain, float/bool/empty-list serialize
- 2499-2510: Cross-module runtime — text, bool, match, lambda apply, 2-hop, codebase insert
- 2511-2518: Parser+type edges — complex nested, nested list, do/handle parse+elab, lambda elab
- 2519-2520: Certification

### Version

v3.9.0 — loader depth, storage adapters, elaborate depth, cross-module runtime.
1543 verifications (1490 dogfood + 53 unit tests).
