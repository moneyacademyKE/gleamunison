# ADR 0027: Integration of Community Library Packages

## Context
1. **Manual FFI Boilerplate**: We previously maintained custom Erlang FFI wrappers (`file_read`, `file_write`, `file_delete`) in `gleamunison_ffi.erl` for basic file operations.
2. **Inspect-based Type Display**: The interactive REPL printed type checking outputs using the raw constructor structures (`string.inspect(typ)`), which is verbose and hard for users to read.
3. **Fragile Parser Verification**: We relied on manual equality assertions for complex parser AST validations, which is boilerplate-heavy and fragile to layout changes.

## Decision
1. **Adopt simplifile**: Replace Erlang FFI file operations with target-agnostic calls to the community package `simplifile`.
2. **Adopt glam**: Create `type_pretty.gleam` utilizing `glam/doc` to format type structures into clean, readable Unison-style strings in the REPL.
3. **Adopt birdie**: Introduce snapshot testing (`birdie`) for AST parsing and pretty printing verification.

## Consequences
- Removed legacy Erlang FFI boilerplate and exports.
- Improved the REPL experience with Wadler-Leijen-style layout documents.
- Standardized snapshot testing to accelerate parser/AST development cycles.
