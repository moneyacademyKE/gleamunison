# Architectural Decision Record (ADR) 0037: REPL Eval/IO Decomposition

## Context

The original REPL module (`repl.gleam`) combined evaluation logic, I/O accumulation, and the read-eval-print loop orchestration in a single module. As the REPL grew to support multi-line input with bracket counting (ADR-0033), spelling suggestions via Levenshtein distance, and dynamic module purging (ADR-0024), the combined concern approached the 250 LOC limit.

The I/O accumulation loop (reading lines, tracking bracket depth, determining when input is complete) is a fundamentally different concern from the evaluation pipeline (parse → elaborate → typecheck → compile → load → eval → print result).

## Decision

Decompose the REPL into three modules:

1. **`repl_io.gleam`**: Input accumulation. Tracks bracket depth via lexer token stream (ADR-0035). Counts open/close parentheses and brace pairs. Detects string boundaries to avoid counting brackets inside literals. Returns `Ready(List(Token))` or `Incomplete(Int)` (remaining depth).
2. **`repl_eval.gleam`**: Evaluation pipeline. Takes a token list and runs the full pipeline: parse, elaborate, typecheck, compile, load, eval. Implements spelling suggestions via depth-limited Levenshtein distance on `NameNotFound` errors. Handles module purging on redefinition.
3. **`repl.gleam`**: Orchestrator. Loops: read via `repl_io` → evaluate via `repl_eval` → print result → repeat. Manages the persistent codebase and loader state across REPL sessions.

## Status

Accepted.

## Consequences

- Each module stays under 250 LOC.
- `repl_io` can be tested independently with token sequence inputs.
- `repl_eval` can be tested independently with pre-tokenized expressions.
- `repl.gleam` is a thin loop with minimal logic, making the REPL flow trivially inspectable.
- Future I/O backends (e.g., WebSocket REPL, HTTP endpoint eval) only need to replace `repl_io`.
