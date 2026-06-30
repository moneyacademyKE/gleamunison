# Rich Hickey Gap Analysis: Gleamunison (v3.4.0) vs. Latest Unison (v1.1.0/1.3.0) & Gleam (v1.17.0)

This document performs a thorough and comprehensive **Rich Hickey Gap Analysis** evaluating the current state of the `gleamunison` runtime (v3.4.0) against the capabilities of the latest releases of Unison (v1.1.0/1.3.0, released early 2026) and Gleam (v1.17.0, released June 2026).

---

## 1. Feature Set Comparison

The following table summarizes the capability differences across the three systems:

| Capability Area | Latest Unison (v1.1.0/1.3.0) | Latest Gleam (v1.17.0) | Gleamunison (v3.4.0) |
| :--- | :--- | :--- | :--- |
| **Escript Support** | N/A | **Native compiler export** (`gleam export escript`) | Custom build pipeline script (`build_escript.sh`) |
| **AI Integration** | **Model Context Protocol (MCP)** tools for LLM codebase navigation | N/A (Standard LSP support) | No MCP/AI interface; CLI and S-expression REPL only |
| **Dependency Evolution** | **Git-style patch lists** (`diff.update` / `patch`) for hash updates | Textual module updates (recompile-all) | Instant replacement (unloads and hot-swaps module) |
| **Code Graph Querying** | **Dependents / Dependencies** commands in UCM & Share | N/A (Project-based text imports) | Internal DETS reference checks (`list_refs`), no user CLI |
| **Constant Prototyping** | Supports `todo` in constants | **Supports `todo` in constants** | `todo` (holes) only allowed in terms/bodies |
| **Error Diagnostics** | Context-aware spelling hints and type suggestions | **Context-aware type suggestions** | Basic spellcheck in term bindings, none in type resolution |

---

## 2. In-Depth Feature Difference Analysis

### 2.1. AI Integration and Model Context Protocol (MCP)
- **Latest Unison**: UCM (Unison Code Manager) acts as an MCP server. This exposes tool endpoints for AI agents, allowing them to query type signatures, look up term details by hash, check dependents, and browse documentation programmatically using JSON-RPC.
- **Gleamunison**: Only exposes a standard text REPL and a HTTP server (`gleamunison_http.erl`) displaying a dashboard. LLMs must read source files or interact via raw shell commands, which limits agent efficiency.

### 2.2. Dependency Evolution & Patching
- **Latest Unison**: Changing a content-addressed definition does not modify it in-place. Unison stores a "patch" mapping the old hash to the new hash. It uses `diff.update` to preview the ripple effects across the codebase, identifying which dependents are broken (due to type mismatches) and guiding the developer through refactoring.
- **Gleamunison**: red-green compilation instantly generates a new name-spaced module (`m_<hash>.beam`) and loads it. Dependent modules still reference the old hash unless they are manually rebuilt. There is no native "patch" or "diff preview" mechanism to guide transitive updates.

### 2.3. Code Graph Queries (Dependents & Dependencies)
- **Latest Unison**: Code is queried transitively. A user can run `dependents foo` to see all terms in the Merkle DAG that reference `foo`.
- **Gleamunison**: Has `list_refs` in `storage.gleam` to query direct DETS references, but lacks recursive query capabilities or user-facing CLI/REPL commands to print dependency trees.

### 2.4. Native Escript Packaging
- **Latest Gleam**: The compiler has a native subcommand to package projects as standalone escripts.
- **Gleamunison**: Relies on `build_escript.sh`, a custom shell script that compiles Erlang FFI files (`erlc`), compiles Gleam modules, creates a zip archive, and prepends the escript launcher header.

---

## 3. Benefits and Trade-offs

### AI MCP Server Integration
*   **Benefits**: Dramatically improves AI agent pair-programming accuracy. Agents can query code relationships and types directly instead of parsing raw file contents.
*   **Trade-offs**: Adds complexity to the http server. Requires implementing the MCP protocol (JSON-RPC) inside the runtime.

### Git-style Patch List (`diff.update`)
*   **Benefits**: Guarantees codebase consistency; prevents "ghost" references where old code versions linger in the Merkle DAG.
*   **Trade-offs**: Extreme complexity. Implementing a patch engine requires calculating the transitive closure of dependents, typechecking them with the new hash, and managing a mutable patch log in DETS.

### Code Graph Querying (Dependents/Dependencies CLI)
*   **Benefits**: Visualizes the impact of updates immediately. Makes the content-addressed nature of the code visible to the developer.
*   **Trade-offs**: Low overhead. Just a query layer over the existing DETS reference tracker.

### Native Escript Export
*   **Benefits**: Simplifies developer environment setup. Avoids external bash scripts and `zip` system command dependencies.
*   **Trade-offs**: The native Gleam exporter does not package custom Erlang FFI files (`.erl`) from the source directory automatically if they need external build variables. Our custom script is highly tuned for this.

---

## 4. Complexity vs. Utility Analysis

| Feature | Utility (1-10) | Complexity (1-10) | Weighted Power / Complexity Ratio | Recommendation |
| :--- | :---: | :---: | :---: | :--- |
| **Code Graph Querying** | 8 | 3 | **2.67** | **Highest Priority**: Simple lookup over DETS keys. |
| **AI MCP Server Integration** | 9 | 5 | **1.80** | **High Priority**: Expose tools via HTTP API. |
| **Context-Aware Type suggestions** | 6 | 4 | **1.50** | **Medium Priority**: Enhances error print helper. |
| **Git-style Patch Engine** | 10 | 9 | **1.11** | **Low Priority**: Deferred. Too complex for current Phase. |
| **Native Escript Export** | 4 | 5 | **0.80** | **Rejected**: Custom script is robust and faster. |
| **Todo in Constants** | 2 | 3 | **0.67** | **Rejected**: Low developer utility. |

---

## 5. Actionable Recommendations

Based on the weighted analysis, we recommend implementing the following features in sequence:

1. **Graph Query CLI (`dependents` / `dependencies` commands)**:
   - Extend `storage.gleam` to recursively trace references.
   - Expose `(dependents term)` and `(dependencies term)` as built-in REPL commands.
   - Add these query endpoints to the Dynamic Web Dashboard.

2. **AI MCP Tooling Integration**:
   - Leverage the existing HTTP server (`gleamunison_http.erl`) to expose a Model Context Protocol endpoint `/api/mcp` responding to standard JSON-RPC queries.
   - Support `get_definition_type`, `list_dependents`, and `search_names` tools.

3. **Diagnostics Enhancement**:
   - Extend spelling suggestions from bindings to type mismatch reports.
