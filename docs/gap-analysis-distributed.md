# Rich Hickey Gap Analysis: Phase 5 Distributed Topology & Concurrency

> **Status: IMPLEMENTED (v0.8.0).** All four recommendations in Section 4 were implemented: Remote ability with `forkAt`/`await`/`here` in `repl.gleam`/`gleamunison_repl_ffi.erl`, Mnesia storage adapter in `storage.gleam`/`gleamunison_storage.erl`, serializable continuations via `term_to_binary`/`binary_to_term` (see Learning #34), and supervision trees in `gleamunison_sup.erl` with isolated link topology (see Learning #36). This document is retained as historical record of the analysis that informed the implementation.

This document performs a gap analysis on the distributed features (Remote ability, Location-aware compute, Mnesia storage, Supervision trees, and Serializable Continuations) required to transition `gleamunison` into a location-aware, distributed-first programming language.

---

## 1. Feature Set Difference Analysis

| Feature Area | Unison (UCM/Cloud) | Gleamunison (Target) | Gap Explanation |
|--------------|-------------------|----------------------|-----------------|
| **Location representation** | `Location` represents a remote compute container / namespace. | `Location` constructor wrapping Erlang nodes/processes. | Unison uses complex container identifiers; Erlang maps locations directly to node names (e.g. `node@host`). |
| **Code Shipping** | Automatic shipping of missing content-addressed BEAM/dependencies. | Pull-based three-phase sync protocol over HTTP/node sync. | Unison sends serialized syntax trees; Gleamunison syncs `.beam` modules by content hashes, fully utilizing Erlang's VM code loader. |
| **Continuation Capture** | Execution stack serialization. | Closure capture & Erlang binary serialization of active handlers. | Erlang's `term_to_binary/1` can serialize closures if identical module version hashes exist on both nodes. |
| **Distributed Database** | Cloud storage syncing. | Multi-node replicated Mnesia database adapter. | DETS/ETS are single-node; Mnesia provides built-in multi-node transaction replication. |
| **Fault Tolerance** | Container-level recovery. | Supervision Trees for hot-starting crashed actors. | Erlang supervisors natively restart actors while keeping dynamic stack-based handler dictionary states. |

---

## 2. Benefits and Trade-offs

### Remote Ability & Location Representation
- **Benefits:** Complete transparency of execution location; write distributed systems as if writing monolithic single-node functions.
- **Trade-offs:** Latency overhead of network hop is masked; type safety across nodes must be guaranteed.

### Mnesia Storage Adapter
- **Benefits:** Transactional ACID guarantees, replication across multiple nodes, no external database dependencies (pure Erlang/OTP).
- **Trade-offs:** Mnesia tables require schema initialization; overhead is higher than local memory ETS.

### Serializable Continuations
- **Benefits:** Allows pausing execution at any point and resuming on another machine (e.g., distributed map-reduce).
- **Trade-offs:** Captured environment must be fully serializable (no open file descriptors or raw sockets).

---

## 3. Complexity vs. Utility Matrix

| Feature | Utility (1-10) | Complexity (1-10) | Weighted Recommendation |
|---------|----------------|-------------------|-------------------------|
| **Remote Ability & Location** | 9 | 4 | **High Priority**: Core building block for Phase 5. |
| **Mnesia Storage Adapter** | 8 | 3 | **High Priority**: Easy implementation with standard Erlang APIs. |
| **Supervision Trees** | 7 | 5 | **Medium Priority**: Standard OTP structure, highly useful for reliability. |
| **Serializable Continuations** | 10 | 6 | **High Priority**: Erlang term serialization provides this natively. |

---

## 4. Actionable Recommendation

Based on the weighted power vs. complexity analysis, we recommend:
1. **Bootstrap the `Remote` ability** and the `Location` type in the typecheck environment using type variables to avoid compiler modifications.
2. **Implement Mnesia Storage Adapter** in `storage.gleam` and `gleamunison_storage.erl`.
3. **Expose Serializable Continuations FFI** via `erlang:term_to_binary` and `erlang:binary_to_term` wrapper routines.
4. **Implement Supervision Trees** using Erlang's supervisor module to orchestrate the codebase servers and HTTP servers dynamically.

We will proceed with these recommended actions next.
