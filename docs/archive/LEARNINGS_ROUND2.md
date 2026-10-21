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

## 8. Polled Recovery in Supervisor Trees
Using a fixed delay like `timer:sleep/50` for asynchronous service recovery checks in supervisor test suites is fragile under heavy load. A recursive polling loop with retries ensures reliable test verification without timing assumptions.

## 9. Transient Table Ownership in RPC Connected Nodes
Named ETS tables created by RPC connection worker processes are deleted when the RPC finishes and the transient worker process terminates. Initializing shared ETS tables in a long-lived, supervisor-backed background process is necessary to ensure state persistence across RPC lifecycles.

## 10. DETS Lookup Exception Semantics
DETS table lookups (`dets:lookup/2`) throw a `badarg` exception if the table reference is closed or invalid, rather than returning an `{error, Reason}` tuple. Code coverage runners and test suites must catch `badarg` or ensure the target table is open, as closed-table exceptions bypass standard case guards.

## 11. Erlang Cover-Compiled code:which Behavior
Calling `code:which(M)` on an Erlang module that has been cover-compiled returns the atom `cover_compiled` rather than the filesystem path. Test runners that dynamically query module paths must store compile paths beforehand or handle the `cover_compiled` atom case explicitly.

## 12. Odd-Length Hex Decoding Failures
Erlang's hex decoding functions throw a `badarg` exception when called with odd-length binaries (e.g. `<<"abc">>`). FFI handlers must enforce even-length validation before calling decode functions to prevent crashing in low-level database or sync modules.

## 13. Token Signature Conservatism in Lexer Refactoring
When refactoring tokenizers or lexers that are widely imported or integrated by test suites, avoid changing function signatures (e.g. `tokenize: String -> List(Token)`). Instead, introduce new invalid token variants (e.g. `UnterminatedString(String)`) to propagate syntactic errors downstream without breaking existing API integrations.

## 14. Monadic Error Propagation vs. Fallback Unwrapping
Swallowing inner compiler or AST elaboration errors via `result.unwrap` allows semantically invalid programs to compile with silent, incorrect defaults. Utilizing Gleam's monadic `result.try` ensures that errors bubble up the elaboration stack correctly while preserving original caller interfaces and contexts.

## 15. FFI Map Key and Type Alignment
FFI layers that return maps to Gleam should use binary strings as keys rather than Erlang atoms. This aligns the output structure with Gleam's native string-keyed dictionary implementation (`Dict(String, b)`), preventing runtime key representation leakage. Additionally, ensure success-branch FFI declarations accurately match Erlang collection structures (e.g. lists vs single elements) to avoid hidden compiler type safety violations.
