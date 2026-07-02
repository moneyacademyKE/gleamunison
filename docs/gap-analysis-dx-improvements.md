# Rich Hickey Gap Analysis: Developer Experience (DX) Improvements

This document performs a thorough **Rich Hickey Gap Analysis** evaluating the developer experience (DX) of the **gleamunison** development workflow, comparing it with the capabilities of mainstream language managers (like Unison's `ucm`), LSP integrations, and trace-driven environments.

---

## 1. Feature Set Comparison

| DX Capability | Ideal Developer Experience (e.g., Unison UCM, Darklang, Gleam LSP) | Current gleamunison (v3.4.0) | Gap |
| :--- | :--- | :--- | :--- |
| **Scratch-file Watcher** | A daemon processes `.u` scratch files on save, typechecks, and provides CLI feedback instantly. | Raw S-expression text file loading or manual REPL command definition. | No automatic compiler watcher for scratch files to load them into the local DB. |
| **Interactive Code Viewing** | `view <name>` prints source code reconstructed from the codebase Merkle DAG, striping names/annotations. | DB browser on the web dashboard only; REPL lacks inline source viewing. | No terminal-level code reconstruction / AST viewing command. |
| **Dependency Graph Queries** | `dependents <name>` and `dependencies <name>` query transitive relationships immediately. | Reference checking exists inside `storage.gleam` (`list_refs`), but is not user-facing. | No CLI commands to query/visualize the code graph. |
| **Type-directed Search** | `find <type>` queries definitions matching a specific signature (e.g., `Int -> Text`). | No type index query system; name-based searches only. | Type signatures are not indexed for semantic lookups. |
| **Live Trace Replay** | Editor loads real runtime execution traces (arguments, closures) to evaluate code against. | HTTP dashboard traces listed; REPL cannot access or load traces into scope. | No FFI link between tracing database and execution environment. |
| **AST Formatter** | Format S-expression code with a standard opinionated layout (like `gleam format` or `rustfmt`). | Manual spacing and bracket counting. | Lack of automatic S-expression parser/formatter. |

---

## 2. In-Depth Feature Difference Analysis

### 2.1. Scratch-file Watcher (`watch-scratch` loop)
*   **Ideal State**: Developers write temporary drafts in a `scratch.unison` file. UCM watches this file. Saving the file triggers the compiler to parse all expressions. Top-level definitions are checked for correctness and can be persisted to the database via `add` or `update`.
*   **Current State**: In `gleamunison`, developers must either write expressions in a text file and load it manually, or type them directly into the REPL, which lacks syntax coloring and auto-completion.

### 2.2. Interactive Code Viewing and Graph Queries
*   **Ideal State**: Running `(view 'my_function)` in the REPL prints the pretty-printed AST. Running `(dependents 'my_function)` prints a list of all definitions referencing it.
*   **Current State**: While the AST is stored inside DETS, there is no command to pretty-print the AST back to a Lisp S-expression in the terminal. Tracing dependents requires querying the raw DETS table via Gleam code.

### 2.3. Live Trace Integration for REPL Debugging
*   **Ideal State**: A handler throws an error. The runtime captures the dynamic stack frame and inputs, saving it under an ID (e.g., `trace_42`). In the REPL, the developer can run `(load-trace 42)` to bind all input variables to the trace values, allowing them to step-evaluate the code under identical conditions.
*   **Current State**: Traces are saved in ETS and pushed to the dashboard via Server-Sent Events, but there is no mechanism to bind them to the local evaluation environment in the REPL.

---

## 3. Benefits and Trade-offs

### Automatic Scratch-file Watcher
*   **Benefits**: Dramatically reduces iteration cycles. The developer only interacts with their text editor. Compilation errors appear instantly without leaving the editor.
*   **Trade-offs**: Requires running a filesystem polling process. Hashing/typechecking must be fast enough to run on every file write.

### Interactive Code Viewing & Graph Query Commands
*   **Benefits**: Codebase navigation becomes self-contained within the terminal. Developers do not need to switch between the browser dashboard and their editor.
*   **Trade-offs**: Requires writing a pretty-printer that reconstructs readable source text from raw AST terms (e.g., converting variable indices back to human-readable names).

### Live Trace Binding in REPL
*   **Benefits**: Simplifies debugging of complex, stateful algebraic effect flows. Provides instant feedback on fixing production bugs using real payloads.
*   **Trade-offs**: Serializing dynamic closures and FFI values into a database can be complex and may leak sensitive credentials (e.g., API keys).

---

## 4. Complexity vs. Utility Analysis

| Feature | Utility (1-10) | Complexity (1-10) | Weighted Power / Complexity | Recommendation |
| :--- | :---: | :---: | :---: | :--- |
| **Interactive Code Graph Queries (`dependents` / `dependencies`)** | 8 | 3 | **2.67** | **Highest Priority**: Simple wrapper over existing DETS reference lookups. |
| **Scratch-file Watcher Daemon** | 9 | 4 | **2.25** | **High Priority**: Watch a `scratch.lisp` file and compile/load it on save. |
| **AST Source Reconstruction (`(view name)`)** | 7 | 5 | **1.40** | **Medium Priority**: Requires variable name-reconstruction logic. |
| **Live Trace Binding (`(load-trace id)`)** | 8 | 7 | **1.14** | **Deferred**: Complex serialization of environment closures. |
| **S-expression Code Formatter** | 5 | 5 | **1.00** | **Rejected**: S-expressions are simple enough to format manually or using general Lisp formatters. |

---

## 5. Actionable DX Recommendations

We recommend implementing the following DX enhancements in sequence:

### 1. File-based Scratch Watcher (`bb watch-scratch`)
*   Implement a lightweight Babashka script `scripts/watch_scratch.clj` that monitors a `scratch.lisp` file in the project root.
*   Upon detecting file changes, the script reads the contents, sends them to a local runtime HTTP endpoint (e.g., `/api/verify`), and displays compilation/typecheck errors in the console.

### 2. Codebase Query Commands in REPL
*   Extend the REPL to support `(view name)`, `(dependents name)`, and `(dependencies name)`.
*   `(view)` should look up the term, resolve its de Bruijn variable indices back to synthetic names (using an alpha-equivalency resolver), and print S-expression code.
*   `(dependents)` and `(dependencies)` should recursively query DETS and print a formatted tree diagram.
