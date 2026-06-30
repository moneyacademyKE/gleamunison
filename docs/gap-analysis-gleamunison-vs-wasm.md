# Rich Hickey Gap Analysis: BEAM-based Gleamunison vs. Cloudflare Workers WASM (`gleamunison-cf`)

This document performs a comprehensive **Rich Hickey Gap Analysis** evaluating the current central BEAM-native `gleamunison` runtime against the WebAssembly-based Cloudflare Worker implementation (`gleamunison-cf` compiled via the `gleamwasm` Rust compiler).

---

## 1. Feature Set Comparison

| Capability Area | central `gleamunison` (BEAM) | `gleamunison-cf` (WASM / Cloudflare) | Gap / Resolution |
| :--- | :--- | :--- | :--- |
| **Execution Model** | **Dynamic Compilation & Loading** (emits Erlang, compiles to BEAM bytecode, loads via `code:load_binary`) | **Ahead-of-Time WASM Compilation** (compiled from static Gleam using `gleamwasm` to `.wasm` files) | WASM target must execute code using a static AST interpreter or JS FFI layer; direct compilation is prohibited by V8 sandbox. |
| **Runtime Concurrency**| **Preemptive Actor Model** (OTP processes, supervisors, and process linking) | **Single-threaded Event Loop** (JavaScript V8 microtask queue) | Erlang mailboxes and lightweight scheduling are replaced by async JS Promises. |
| **State & Scope Stack** | **Process Dictionary** (`$ability_stack` for algebraic effect stack frames) | **Linear Memory / KV Store** (Simulated state map via FFI stubs or global array) | CF lacks a process heap; effect frames are managed in JavaScript request context. |
| **Database & Storage** | **DETS / ETS / Mnesia** (replicated ACID tables and transaction layers) | **Cloudflare KV Namespace** (external JS fetch bridge) | File system operations are mapped to asynchronous KV `get`/`put` calls. |
| **FFI Integration** | **Erlang BIFs & NIFs** (75 OTP-bound calls for calendar, crypto, loading) | **JavaScript imports / pure WASI** (12 JS stubs or 17 self-contained WASM stubs) | Erlang modules are replaced by equivalent JS helper functions imported into WASM. |
| **Gleam Language Coverage**| **100% of Gleam Language** (supports recursive lists, curried calls, pattern matches, custom types) | **Partial Subset** (supports primitive i32/f64, let bindings, if, tagged ADTs, no closures/lists/strings) | `gleamwasm` compiler prototype is not yet feature-complete to compile the entire 4,271 lines of Gleam. |

---

## 2. In-Depth Feature Difference Analysis

### 2.2. Dynamic Compilation vs. Static WASM
- **BEAM (`gleamunison`)**: Operates as a self-evaluating language. When a user defines a function in the REPL, it parses the S-expression, typechecks it, generates Erlang source code, compiles it to BEAM bytecode dynamically, and loads it into the running VM.
- **WASM (`gleamunison-cf`)**: The V8 isolate environment blocks dynamic compilation (`eval` and `WebAssembly.compile` are disabled). The WASM module is compiled ahead-of-time. Therefore, compiling user S-expressions dynamically at runtime is impossible. The WASM module must act as a static **interpreter engine** that reads S-expression structures as data and evaluates them.

### 2.3. Concurrency and Process Scheduling
- **BEAM (`gleamunison`)**: Uses native OTP supervisors to link and monitor process lifecycles. Processes are scheduled preemptively.
- **WASM (`gleamunison-cf`)**: Runs in a single-threaded cooperative event loop. Spawning isolated parallel actors is not supported natively; concurrency is achieved using async fetches or JS microtasks.

### 2.4. FFI and Platform Dependencies
- **BEAM (`gleamunison`)**: Integrates natively with the Erlang ecosystem. It relies on 75 FFI calls for critical services like dynamic compilation (`compile:forms`), process spawning (`spawn`), and crypto (`crypto:hash`).
- **WASM (`gleamunison-cf`)**: Relies on a JS import adapter layer. The adapter maps Erlang-specific FFI calls to web platform APIs (e.g. mapping `crypto:hash` to the Web Crypto API, and `file:write_file` to Cloudflare KV bindings).

---

## 3. Benefits and Trade-offs

### Central BEAM Node
*   **Benefits**: Full language expressiveness, JIT-optimized execution speed, robust Actor concurrency, transactional Mnesia storage, and true dynamic module hot-swapping.
*   **Trade-offs**: Heavy footprint (100MB+ memory), slower boot times, and operational clustering complexity.

### Cloudflare Worker WASM Isolate
*   **Benefits**: Ultra-lightweight footprint (<5MB memory), sub-5ms cold starts, global edge routing, and zero-devops serverless scaling.
*   **Trade-offs**: Performance penalty of running an AST interpreter instead of compiled bytecode; lack of native actor scheduling; and KV eventual consistency latency.

---

## 4. Complexity vs. Utility Matrix

We assess the architectural paths for integrating the WASM targets into the codebase:

| Implementation Path | Complexity (1-10) | Utility (1-10) | Power / Complexity Ratio | Recommendation |
| :--- | :---: | :---: | :---: | :--- |
| **Deploy static AST Interpreter to WASM** | 5 | 9 | **1.80** | **Accepted**: Runs the full Gleamunison runtime on Cloudflare without compiling at runtime. |
| **Port Erlang FFI to JavaScript FFI** | 6 | 8 | **1.33** | **Accepted**: Essential for executing the parser and typechecker on the V8 host. |
| **Add full Wasm-GC support to compiler** | 9 | 6 | **0.67** | **Deferred**: Implementing full Wasm-GC lists and closures in Rust is high effort. |
| **Dynamic WASM runtime compiler** | 10 | 2 | **0.20** | **Rejected**: Blocked by Cloudflare's platform security policies. |

---

## 5. Actionable Recommendations

To bridge the gap between the BEAM central node and the Cloudflare Workers WASM environment, we recommend:

1. **Implement a Pure Gleam S-Expression AST Interpreter**:
   - Do not attempt to compile S-expressions to WASM bytecode at runtime.
   - Build a tree-walking interpreter directly in Gleam (`interpreter.gleam`) that evaluates S-expression data structures against a lexical environment.
   - Compile this interpreter module to WASM via `gleamwasm` using the static linear-memory target.

2. **Establish a Dual-Target FFI Layer**:
   - Standardize FFI signatures so they compile to either Erlang (`.erl`) or JavaScript (`.ffi.js`) depending on the build target.
   - Implement a JS bridge for file system operations that reads/writes directly from/to Cloudflare KV namespaces.

3. **Merkle Sync Integration**:
   - Use the central BEAM node to compile and verify definitions, then push the validated S-expression ASTs directly to Cloudflare KV, allowing the edge WASM Workers to read and interpret them instantly.
