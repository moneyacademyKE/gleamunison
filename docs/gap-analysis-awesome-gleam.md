# Gap Analysis: awesome-gleam Integration

> **Status: IMPLEMENTED (v0.8.0).** The recommendations were adopted: birdie for snapshot testing (see `test/parser_snapshot_test.gleam`), glam for pretty printing (see `gleamunison/type_pretty.gleam`), simplifile for file I/O (see FFI integration in `gleamunison_ffi_io.erl`), and gleamy_structures for Bimap/PriorityQueue (see `gleam.toml` deps). snag was rejected (loses domain error types). See ADR-0027 (Community Library Package Integration) for the decision record. This document is retained as historical record.

This analysis evaluates the `gleamunison` codebase against community packages from `awesome-gleam`.

## Category Analysis

### 1. Snapshot Testing (`birdie`)
- **Current State**: Manual assertions on parsed and compiled structures in test suite.
- **Proposed State**: Use `birdie` to automatically snapshot and diff AST/eval outputs.
- **Recommendation**: Adopt immediately as a development dependency.

### 2. Pretty Printing (`glam`)
- **Current State**: `string.inspect` in REPL and logs.
- **Proposed State**: Wadler-Leijen-style layout documents to fit output.
- **Recommendation**: Adopt to formatting REPL results.

### 3. File operations (`simplifile`)
- **Current State**: Custom Erlang FFI calls.
- **Proposed State**: Target-agnostic community library.
- **Recommendation**: Replace current FFI with `simplifile` to improve target portability.

### 4. CLI Argument Parsing (`glint`)
- **Current State**: Hand-rolled list matching on raw arguments.
- **Proposed State**: Structured CLI framework.
- **Recommendation**: Defer until CLI interface expands.

### 5. Error Handling (`snag`)
- **Current State**: Typed domain-specific error types.
- **Proposed State**: Flat error stacks.
- **Recommendation**: Do not adopt; domain-specific recovery is required for runtime and storage layers.
