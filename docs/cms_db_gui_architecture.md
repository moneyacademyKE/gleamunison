# Architectural Guide: Implementing Databases, CMS, and GUIs in Gleamunison

This guide analyzes how to build complex, user-facing subsystems—specifically **Databases**, **Content Management Systems (CMS)**, and **Graphical User Interfaces (GUI)**—within the content-addressed `gleamunison` runtime ecosystem.

---

## 1. Rich Hickey Gap Analysis: Guest-Space vs. Host-Space

We analyze two fundamental pathways for implementing these subsystems:
1. **Guest-Space (S-expression App)**: Built natively inside `gleamunison` using S-expressions, algebraic effects, and in-memory execution.
2. **Host-Space (FFI/BEAM Primitives)**: Built directly in native Gleam/Erlang (or JS/WASM for web environments) and exposed as compiler builtins.

### Comparative Feature Set

| Subsystem | Guest-Space S-Expression Approach | Host-Space FFI/BEAM Approach |
| :--- | :--- | :--- |
| **Database** | **Immutable Fact Store**: EAVT maps/indexes represented as nested Lisp dictionaries. State coordinated via actor loops (`spawn`, `send`, `recv`). | **Native ETS/DETS/Mnesia**: Direct FFI calls to Erlang's memory tables and ACID disk storage. |
| **CMS** | **Merkle-DAG CMS**: Structured document templates represented as ASTs. Page updates yield new root Merkle hashes. | **Postgres/SQLite Client**: FFI driver connecting to standard relational databases with schema mutations. |
| **GUI** | **Declarative Virtual-DOM**: Guest functions return a UI tree. Events are routed as algebraic effect handler requests. | **Erlang WxWidgets / JS DOM**: Host-level imperative window rendering or direct browser DOM manipulation. |

---

## 2. Feature & Architectural Differences

### 1. Database (Purity vs. Performance)
* **S-Expression Fact Store**: The database state is represented as a pure, immutable value. Every write returns a new version of the database. 
  * *Benefit*: Bitemporal query engines, state snapshots, and time-travel debugging are trivial because database versions are just value nodes in a graph.
  * *Complexity*: High memory usage due to nested S-expression pairs and garbage collection pressure in the interpreter.
* **Native FFI Store**: Leverages Erlang's raw ETS tables or disk-based DETS.
  * *Benefit*: Extremely fast read/write throughput; integrates with distributed node clustering out-of-the-box.
  * *Complexity*: Mutates global state; requires FFI boundary serialization and custom cleanup guards.

### 2. CMS (Cryptographic Integrity vs. Traditional Mutation)
* **Merkle-DAG CMS**: The CMS treats content as code. Since everything is content-addressed, a webpage or article is a compiled hash. A release is a commit hash pointing to a tree of page hashes.
  * *Benefit*: Perfect auditability, offline-first synchronization, zero-deploy changes, and immunity to SQL injection.
  * *Complexity*: Every minor typo edit changes the page's cryptographic identity, requiring parent hash recalculations up to the root.
* **Traditional DB CMS**: Uses SQL tables to store content strings and templates dynamically.
  * *Benefit*: Compatibility with existing headless editor workflows and rich text parsers.
  * *Complexity*: High coupling to database state, prone to SQL injections, and lacks structural version control.

### 3. GUI (Declarative Effects vs. Imperative Painting)
* **Declarative Virtual-DOM**: Guest functions emit an AST representing the layout (e.g. `(div (class "btn") "Click Me")`). A JS/WASM host layer diffs the tree and patches the DOM. User interactions are dispatched back to the guest process via algebraic effects (e.g., calling an `onClick` operation).
  * *Benefit*: Sandboxed, portable, reactive, and easily testable (effects can be mocked in unit tests).
  * *Complexity*: Latency at the FFI loop boundary.
* **Imperative Native GUI**: Calls underlying C/C++ libraries (like Erlang's WxWidgets).
  * *Benefit*: Direct desktop rendering without browser dependencies.
  * *Complexity*: Completely breaks sandboxing safety and edge-workers portability.

---

## 3. Complexity vs. Utility Matrix

| Subsystem | Approach | Complexity | Utility | Recommendation |
| :--- | :--- | :--- | :--- | :--- |
| **Database** | Native FFI (ETS/DETS) | Medium | Very High | **Use Host-Space FFI** for storage; expose transaction states as pure values. |
| **CMS** | Merkle-DAG (S-expr) | Low | High | **Use Guest-Space** (treat content as code) to maximize sync capabilities. |
| **GUI** | Virtual-DOM (WASM/JS) | High | Very High | **Use Hybrid Model**: Guest emits declarative layout, Host JS renders. |

---

## 4. Actionable Evolution Path

If you are building these subsystems in `gleamunison`, structure them as follows:

1. **Database**: Wrap Erlang’s native DETS/ETS as FFI Builtins using the **FFI Jet pattern**. This keeps data lookups fast while maintaining a pure query interface in the guest environment.
2. **CMS**: Implement a static layout generator in guest-space S-expressions. Pages should be cached under content hashes in the codebase, and rendered via `gleamunison/template`.
3. **GUI**: Build a browser-based WASM runtime target. The guest code outputs a virtual DOM tree (nested S-expression lists), and a lightweight host JS listener handles rendering and pipes actions back into the VM loop.
