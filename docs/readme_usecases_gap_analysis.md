# Gap Analysis: Expanding Gleamunison Usecases

A Rich Hickey-style Gap Analysis comparing standard BEAM architectures and classical Unison applications with our expanded 20+ unique usecases for Gleamunison.

---

## 1. Feature Set Difference Analysis

| Dimension | Standard BEAM (Erlang) | Classical Unison | Gleamunison (Target) |
|---|---|---|---|
| **Hot Swapping** | Name-based (max 2 versions) | None (no actor model) | Hash-based (unbounded versions, GC-controlled) |
| **Sandboxing** | Process boundary only (no IO block) | Compiler rows only (no VM boundaries) | Hybrid process-dict stack + process CPU limit |
| **Code Shipping** | Relies on manual code loading | AST serialization | Binary module sync + dynamic FFI loading |
| **Determinism** | Transient VM state pollution | Pure terms | Replayable continuations via mock handlers |

---

## 2. Explanation of Key Feature Differences

* **Hot Swapping**: Erlang restricts modules to two active versions. Gleamunison compiles functions into hash-named modules (`m_<hash>`), enabling unbounded hot-swapping of stateful actor behaviors without collision.
* **Sandboxing**: Standard Erlang cannot block a process from calling `:file` or `:os` functions if they are in the codebase. Gleamunison intercepts all side effects using algebraic effect handlers, allowing secure multitenancy.
* **Code Shipping**: Shipping compiled bytecode directly allows edge nodes to execute remote computations at native speed without bundler/compiler overhead.

---

## 3. Complexity vs. Utility for Usecase Expansion

| Usecase Group | Complexity (1-10) | Utility (1-10) | Recommendation |
|---|---|---|---|
| **Edge Compute & Migrations** | 7 | 9 | **High Priority**: Promotes BEAM distribution. |
| **Secure Multi-tenant SaaS** | 5 | 9 | **High Priority**: Highlights sandboxed effects. |
| **Replayable Debugging & Logs** | 4 | 8 | **Medium Priority**: Improves diagnostic toolchains. |

---

## 4. Actionable Recommendation

Update the project `README.md` to showcase all 23 unique usecases, categorized by their primary system value (Hot Upgrades, Secure Sandboxing, Distributed Compute, and Debuggability).
