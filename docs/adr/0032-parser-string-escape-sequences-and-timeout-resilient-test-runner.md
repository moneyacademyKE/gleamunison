# ADR-0032: Parser String Escape Sequences and Timeout-Resilient Test Runner

## Status
Accepted

## Context
1. **JSON Strings Parsing Gaps:** Playbook Level 96 requires parsing JSON payloads nested inside string literals, e.g. `(define json-str "{\"name\": \"Alice\"}")`. Our lexer parsed the backslash as a standard character and the inner double quotes as string terminators, causing S-expression parse errors and false-positive failures.
2. **Infinite Loops and REPL Hangs:** Stalls in the 1000-level playbook suite blocked automation. When the REPL hung (e.g. from recursive loops or reading empty lines), the test runner blocked indefinitely on stdin/stdout reads.

## Decision
1. **Parser String Escapes:** We extended the `read_string` tokenizer logic in `parser.gleam` to recognize backslash escapes (`\"`, `\n`, `\\`). If a backslash is encountered, the subsequent character is processed correctly, and the string accumulator is updated.
2. **Timeout-Resilient Runner:** We refactored `eval-expr` in `run_playbook_tests.clj` to wrap REPL evaluations in a Clojure `future` with a 5-second `deref` timeout. If a timeout occurs, the runner terminates the blocked REPL process, starts a fresh one, and logs the issue without halting the entire test suite. Exit/quit/blocking calls are also filtered out.

## Consequences
- The parser now successfully tokenizes nested string payloads, solving Level 96 and enabling correct JSON integrations.
- The playbook test suite runs reliably to completion in under 60 seconds.
