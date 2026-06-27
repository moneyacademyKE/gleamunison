# ADR 0024: REPL Module Purging, Stateful/File FFI, and Dynamic Web Dashboard

## Context
1. **REPL Redefinitions**: Redefining an existing name in the REPL compiles a new module. In Erlang, loading a new version of an already loaded module can lead to collision errors or keep stale versions if not purged first.
2. **Stateful and File Operations**: Dogfooding advanced levels requires stateful computations (mutable cells) and file I/O operations from within functional code.
3. **Web Dashboard Interaction**: A web interface is needed to showcase dynamic evaluation and state interactions on the BEAM.

## Decision
1. **Dynamic Module Purging**: Explicitly call `code:delete/1` and `code:purge/1` via FFI before loading a compiled module binary during redefinition and evaluation in the REPL.
2. **State and File FFI**: Expose Erlang process dictionary operations (`erlang:get/1`, `erlang:put/2`) and file operations (`file:read_file/1`, `file:write_file/2`, `file:delete/1`) as FFI-backed builtins.
3. **VM-Native HTTP Server**: Implement a lightweight TCP/HTTP server in an Erlang FFI module (`gleamunison_http.erl`) serving a premium, responsive glassmorphism web dashboard. Provide endpoints for dynamic evaluation (`/eval`) and process dictionary state interaction (`/increment`).
4. **Genesis Escript Bundling**: Compile all `src/m_*.erl` files and include their `.beam` binaries in the escript ZIP archive, ensuring standalone execution.

## Consequences
- Clean, collision-free module redefinitions in the REPL.
- Safe, process-isolated mutable state and file I/O operations.
- Dynamic web-based dashboard running natively on the Erlang VM without external assets.
- Fully self-contained standalone binary with pre-packaged genesis stubs.
