# Gap Analysis: Cloudflare Workers and WebAssembly Compatibility

## 1. Executive Summary
This document analyzes the technical feasibility and architectural paths for running the `gleamunison` runtime inside the Cloudflare Workers serverless environment, specifically targeting WebAssembly (WASM) and JavaScript.

---

## 2. Rich Hickey Gap Analysis (State, Identity, Value)

### Identity & Value
- **Current Model**: Definition identity is defined by a `DefinitionRef` which is the SHA256 hash of the serialized AST (value).
- **CF Workers / WASM Model**: Fully compatible. SHA256 is native, and immutable values (ASTs) map cleanly to JSON or binary formats.

### State & Execution
- **Current Model**:
  - Dynamically compiles AST to Erlang source.
  - Compiles source to BEAM bytecode at runtime via `compile:forms/2`.
  - Dynamically loads BEAM bytecode into memory using `code:load_binary/3`.
  - Algebraic effects handler stack is managed using the thread-local Process Dictionary.
- **CF Workers / WASM Model**:
  - **Dynamic Code Blockers**: V8 isolates block dynamic evaluation (`eval`, `new Function`) and dynamic WebAssembly compilation (`WebAssembly.compile`, `WebAssembly.instantiate` from raw bytes).
  - **Single-Threaded Cooperative Event Loop**: V8 is single-threaded per request context; no native preemptive processes or mailboxes.
- **The Gap**: Dynamic code loading and VM-level compilation are prohibited by Cloudflare's security sandbox.

---

## 3. Feature Set Differences

| Feature Area | Erlang/BEAM Runtime (Current) | Cloudflare Worker / WASM | Resolution / Gap Strategy |
| :--- | :--- | :--- | :--- |
| **Dynamic Execution** | `code:load_binary/3` (native dynamic loading) | Blocked (`eval`/`WebAssembly.compile` disallowed) | Use an **AST Interpreter** (static WASM/JS executing AST data) or **Dynamic Workers Loader API**. |
| **Concurrency** | Preemptive actor processes (`spawn`/`send`/`recv`) | Single-threaded cooperative event loop | Implement cooperative scheduler in JS/Gleam. |
| **Algebraic Effects** | Dynamic handler stack in Process Dictionary | Single-threaded request context | Map handler stack to a request-scoped array/stack in JS. |
| **Storage** | ETS / DETS / Mnesia (disk/RAM database) | Read-only disk; Cloudflare KV, D1, Durable Objects | Reimplement `storage.gleam` to wrap Cloudflare KV or Durable Objects. |
| **Dynamic Purging** | `code:soft_purge` & `code:delete` | Blocked (static deployment module) | For interpreters, eviction from AST cache in memory/KV. |
| **FFI Implementations** | Erlang FFI (`.erl` files) | JavaScript / WASM imports | Port Erlang FFI to JavaScript FFI. |

---

## 4. Complexity vs. Utility Analysis

| Path | Complexity | Utility | Recommendation |
| :--- | :--- | :--- | :--- |
| **Dynamic WASM compilation** | Extreme (Blocked by platform) | High (Allows dynamic WASM execution) | **Rejected**: Technically impossible due to platform security blocks. |
| **Ahead-of-Time (AOT) compiler** | High | Medium | **Rejected**: Breaks the live-upgradable and REPL-driven nature of Gleamunison. |
| **Gleam JS compilation + AST Interpreter** | Medium-Low | High | **Recommended**: Compile parser, typechecker, and an AST interpreter to JS. Run without platform constraints. |
| **Cloudflare Dynamic Workers Loader** | Medium-High | Medium | **Alternative**: Useful for tenant isolation, but adds high cold-start latencies. |

---

## 5. Actionable Recommendation
1. **Target JavaScript compilation**: Compile the Gleam codebase using `gleam build --target=javascript`.
2. **Implement an AST Interpreter**: Replace the Erlang bytecode emitter (`compile.gleam`) with a lightweight AST interpreter loop for evaluation.
3. **Port FFI to JS**: Replace Erlang `.erl` FFI files with matching `.ffi.js` JavaScript FFI files.
4. **Adapter Storage**: Implement a Cloudflare KV storage adapter.
