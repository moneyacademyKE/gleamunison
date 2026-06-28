# ADR 0044: Content-Addressed Jet Registry

## Context
1. **Performance of Content-Addressed Code**: Dynamically compiling and evaluating AST nodes in a content-addressed runtime can be slow for highly intensive math, cryptographic, or network operations.
2. **Urbit Jets Pattern**: Urbit's Nock VM achieves performance by mapping specific function battery hashes to native C/Rust functions (jets) that run outside the virtual machine.
3. **BEAM Compiler FFI**: Since the `gleamunison` runtime runs on the BEAM, we can intercept specific pure AST function hashes during compilation and emit native, highly optimized Erlang/Gleam FFI calls instead of dynamically generated code.

## Decision
1. **Jet Mapping Registry**: Propose a static compile-time registry mapping canonical `DefinitionRef` hashes to specific Erlang modules/functions (e.g. mapping a content-addressed SHA256 implementation hash to the native `:crypto` module).
2. **Compiler Interception**: Modify the compiler in `compile.gleam` to check the hash of any dynamic apply or reference. If the hash exists in the jet registry, emit the registered native module and function name directly instead of traversing the dynamic term.

## Consequences
* Massive performance gains for performance-critical standard library functions.
* Purity is preserved: the source codebase remains mathematically pure, while the compiler leverages platform-dependent performance under the hood.
* High extensibility: developers can register new jets for custom libraries.
