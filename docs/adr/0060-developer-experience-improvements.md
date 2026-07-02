# ADR-0060: Developer Experience (DX) Improvements

## Context
As `gleamunison` scales to thousands of playbook levels and complex distributed applications, the developer feedback loop (editing, typechecking, running REPL commands, querying the Merkle DAG) needs optimizations. We performed a Rich Hickey-style Gap Analysis comparing the current workflow with systems like Unison's `ucm`, Darklang's live trace debugger, and modern LSP implementations.

## Decision
Based on our analysis of complexity vs. utility, we made the following decisions:
1. **Accept Scratch-file Watcher (`bb watch-scratch`)**: We will implement a Babashka watcher script that monitors a local `scratch.lisp` file. On save, it compiles and typechecks definitions via a local HTTP endpoint, rendering instant console errors.
2. **Accept REPL-level Code Graph Queries**: We will extend the REPL to support `(view name)`, `(dependents name)`, and `(dependencies name)` commands, utilizing the existing DETS references index.
3. **Defer Live Trace Binding in REPL**: While capturing traces is supported in the dashboard, loading trace bindings directly into the REPL execution scope requires complex environment reconstruction. We will defer this feature to a later phase.
4. **Reject S-expression Formatter**: The Lisp S-expression syntax is highly standardized. We will rely on existing editor tools for Lisp indentation rather than building a custom parser-formatter.

## Consequences
- The feedback loop is reduced from manual REPL command typing/loading to a smooth, editor-integrated save-and-verify workflow.
- Codebase structure and Merkle DAG dependencies are queryable directly inside the terminal.
