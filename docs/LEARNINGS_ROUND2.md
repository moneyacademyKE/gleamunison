# Architectural Learnings — Round 2

## 1. Statefulness inside Pure Record Closures
Gleam's immutable record functions can capture and close over Erlang state (such as an ETS table reference created on initialization). This provides a mutable storage boundary without polluting the pure type signatures.

## 2. Inverted Sync Protocol Hazards
In pull sync, requesting files we already possess is redundant and incorrect. The correct Unison-style protocol must advertise our local hashes first, fetch the difference from the peer, and then request only those missing blobs.

## 3. Local de Bruijn Counter Isolation
Sibling arms in `SMatch` expressions must not share the same mutable/accumulator index allocator. Leaking `next_local` between match cases causes identical variable names in separate arms to receive different de Bruijn indices.
