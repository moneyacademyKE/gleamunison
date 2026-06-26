# Architectural Learnings — Round 2

## 1. Statefulness inside Pure Record Closures
Gleam's immutable record functions can capture and close over Erlang state (such as an ETS table reference created on initialization). This provides a mutable storage boundary without polluting the pure type signatures.

## 2. Inverted Sync Protocol Hazards
In pull sync, requesting files we already possess is redundant and incorrect. The correct Unison-style protocol must advertise our local hashes first, fetch the difference from the peer, and then request only those missing blobs.

## 3. Local de Bruijn Counter Isolation
Sibling arms in `SMatch` expressions must not share the same mutable/accumulator index allocator. Leaking `next_local` between match cases causes identical variable names in separate arms to receive different de Bruijn indices.

## 4. Hash-Partitioned DETS
Bypassing the 2GB DETS limit is possible by dynamically routing hash keys to 16 prefix-indexed files. This increases local zero-dependency database capabilities to 32GB without SQLite compilation complexities.

## 5. BEAM Module Garbage Collection (LRU)
Dynamic bytecode compilation creates memory pressure and atom table leaks. Enforcing an LRU loader cache and executing FFI `code:delete/1` and `code:purge/1` prevents VM memory exhaustion.

## 6. Active Dynamic Scope Stack Protection
Running type/schema validation check guards on every push/pop operation on the process dictionary prevents corruption from manual/external FFI mutations.

## 7. Coordinate Tokenizer
Tokenizing with line and column offset tracking allows recursive-descent parsers to provide detailed parse error coordinate diagnostics.
