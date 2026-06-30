# ADR-0058: Gleamunison BEAM vs. Cloudflare Workers WASM Decisions

## Context
An architectural decision was needed on how the central BEAM-native `gleamunison` runtime maps to the lightweight serverless WebAssembly Cloudflare Workers adapter (`gleamunison-cf`). 

Compiling the entire 4,271 lines of the compiler/runtime to native WebAssembly bytes using the `gleamwasm` Rust compiler is blocked by the runtime requirements of the BEAM (dynamic code loading, hot-swapping, OTP process mailboxes, process dictionary storage, and 75 Erlang FFI dependencies).

## Decision
We established the evolution model for WASM-target integration:
1. **Static AST Interpreter over Compiled Bytecode**: To bypass V8's sandbox restriction on dynamic compilation/loading, the WASM target will run a static S-expression AST interpreter rather than generating dynamic WASM/BEAM bytecode at runtime.
2. **Dual-Target FFI Layer**: Standardize FFI calls to compile to either Erlang or JavaScript dynamically depending on the compiler target, resolving platform-dependent filesystem and crypto library calls.
3. **Merkle Sync Bridge**: The central BEAM node handles dynamic edits, compilation, and validation, then syncs pre-verified S-expression definitions to Cloudflare KV. The edge Workers pull these hashes and evaluate them locally using the static interpreter.

## Consequences
- Dynamic compilation overhead is eliminated at the edge, reducing cold starts to <5ms.
- High developer ergonomics are preserved centrally via the BEAM REPL while achieving massive, low-cost serverless global edge distribution.
