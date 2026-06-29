# ADR-0054: Cloudflare Workers and WebAssembly Compatibility Analysis

## Context
A request was made to investigate the feasibility of compiling `gleamunison` to WebAssembly (WASM) for deployment on Cloudflare Workers.

The current `gleamunison` runtime is a content-addressed execution environment built on the Erlang BEAM VM. It compiles Unison-style Core AST representations into Erlang source strings dynamically, compiles them to BEAM bytecode using `compile:forms/2`, and loads them into Erlang VM process memory via `code:load_binary/3`. It relies heavily on Erlang-specific FFI modules, process dictionary storage for algebraic effects, and ETS/DETS tables for Merkle database storage.

## Decision
We conducted a comprehensive Rich Hickey Gap Analysis and concluded that:
1. **Dynamic Compilation is Blocked**: Cloudflare Workers block dynamic code execution (`eval`, `new Function`, `WebAssembly.compile`) due to V8 isolate security constraints. We cannot dynamically compile AST to BEAM, JS, or WASM at runtime in the Worker.
2. **Dynamic loading via Interpreter is Feasible**: To support dynamic code execution (e.g. interactive REPL or runtime additions), we must shift from a compilation-and-loading model to an **AST Interpreter** model running inside a statically deployed JS/WASM worker.
3. **Target Javascript instead of WASM**: Compile the Gleam codebase to JavaScript (`gleam build --target=javascript`). Porting Erlang FFI modules to JavaScript FFI modules is straightforward and provides native integration with Cloudflare Workers APIs.

## Consequences
- Dynamic compilation (`compile.gleam` and Erlang FFI compile functions) must be bypassed or replaced with an AST interpreter loop.
- Storage must be ported from ETS/DETS to Cloudflare KV / Durable Objects.
- FFI files must be rewritten in JavaScript.
