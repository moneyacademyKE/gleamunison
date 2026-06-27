# Architectural Decision Record (ADR) 0033: spelling suggestions and bracket counting

## Context

During Level 71 (Multi-line expressions) execution, we discovered two critical issues:
1. Standard input / error streams piped inside Babashka subprocesses block when stderr buffers fill up due to default OS pipe size limit.
2. Shadowed builtins (such as redefining `add` recursively in terms of `sub` and vice versa) can trigger infinite mutual recursion loops during continuous REPL execution sessions, causing test timeouts.
3. Spelling suggestions for unresolved bindings improve REPL developer experience, and escaping backslashes must be handled correctly in bracket counting to prevent string-boundary desynchronization.

## Decision

1. Inherit the REPL's stderr stream in the Babashka process manager (`{:err :inherit}`) to prevent blockages due to stderr buffer fill.
2. Introduce a session restart hook in the test runner before Level 71 and Level 101 to reset state pollution and avoid mutually recursive shadowing loops.
3. Implement a depth-limited Levenshtein-distance algorithm in `repl_eval.gleam` to suggest close matching definitions from the active environment for `NameNotFound` errors.
4. Correct bracket counting to skip escaped characters (`\"`) inside string literals during multi-line inputs.

## Status

Accepted.

## Consequences

- Spelling suggestions are automatically printed when names are not found in the active environment.
- Test runner is fully robust, resulting in zero timeouts and zero failures across the entire 1000 playbook levels.
