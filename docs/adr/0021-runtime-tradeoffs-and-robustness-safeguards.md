# ADR 0021: Runtime Tradeoffs & Robustness Safeguards

## Context
As Gleamunison matures towards production readiness, the runtime prototype faces several key constraints and vulnerability vectors:
1. **DETS 2GB file size limit**.
2. **Atom table exhaustion** due to unbounded loaded modules.
3. **Process dictionary corruption** where direct writes to `$gleamunison_handlers` by FFI/external systems bypass stack validations.
4. **Simple parser diagnostics** making syntax debugging difficult.

## Decision
1. **Hash-Partitioned DETS**: Partition definition storage dynamically across 16 different prefix-indexed DETS files, bypassing the 2GB limit while maintaining a zero-dependency local KV footprint.
2. **LRU Code Module Purger**: Wrap `code:delete/1` and `code:purge/1` in the loader to garbage collect old dynamic modules using an LRU cache size limit.
3. **Dynamic Stack Validation Guards**: Enforce schema validations on push/pop operations to throw explicit corrupted-stack exceptions instead of silent badmatches.
4. **Coordinate Tokenizer**: Track coordinate positions (lines & columns) dynamically to yield rich syntactic parse errors.

## Consequences
- Codebase storage expands to 32GB natively on DETS.
- Dynamic compilation cycles are protected against atom table leaks.
- Stack integrity is actively guaranteed, yielding debuggable diagnostics.
- Coordinates enable precise parser error tracking.
