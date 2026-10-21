# Gap Analysis: Gleamunison vs Unison 1.0

A Rich Hickey-style Gap Analysis comparing the lightweight BEAM-native `gleamunison` runtime with the official Unison 1.0 release.

---

## 1. Feature Set Differences

| Feature Area | Unison 1.0 (Official) | Gleamunison (BEAM Runtime) |
|---|---|---|
| **Identity Hash** | SHA3-512 (Term + Type structure) | SHA256 (Term + Type structure) |
| **Primitives** | Builtin `##` prefix escape namespace | Genesis block (Uniform hash space) |
| **Effect Model** | Explicit continuation variable `k` | Implicit stack-based frame (Process dict) |
| **Codebase Store** | SQLite / Event Log (Append-only) | DETS / Mnesia Partitioned KV |
| **Namespaces** | Hierarchical projects & branches | Flat namespace mapping index |
| **Distribution** | `Remote` ability (AST shipping & Cloud) | `Remote` ability (BEAM binary shipping) |

---

## 2. Explanation of Feature Differences

* **Identity Hash**: Unison uses 512-bit SHA3 digests. Gleamunison uses 256-bit SHA256. SHA256 is native on the BEAM, reducing hashing time and storage overhead.
* **Primitives**: Unison's `##` creates a parallel, non-content-addressed space. Gleamunison's Genesis block represents all primitives as uniform content-addressed hashes.
* **Effect Model**: Unison uses explicit CPS continuation variables, allowing handlers to manipulate the stack explicitly. Gleamunison utilizes BEAM process-local state (`erlang:get` / `erlang:put`) and implicit closures, keeping runtime code extremely lightweight.
* **Codebase Store**: Unison stores code in SQLite. Gleamunison uses partitioned DETS (16 hash-prefixed files) and Mnesia for ACID replicated storage, avoiding C-library dependencies.
* **Namespaces**: Unison supports project branches and hierarchical organization. Gleamunison simplifies this with a flat name-to-hash mapping.
* **Distribution**: Unison ships serialized ASTs to execute remotely. Gleamunison compiles terms to Erlang `.beam` files locally, synchronization syncs module binaries, and Erlang's VM loads them dynamically.

---

## 3. Benefits and Trade-offs

### Implicit Stack-Based Effects
* **Benefits**: High performance; minimal runtime code footprint (<100 LOC); matches the BEAM process model perfectly.
* **Trade-offs**: Lack of row polymorphism/handler boundary type checks in the compiler (addressed by compile-time `validate_handler` verification).

### Partitioned DETS & Mnesia
* **Benefits**: Zero external dependencies; standalone escript remains ~1.2 MB; Mnesia provides built-in cluster replication.
* **Trade-offs**: DETS tables can get corrupted if processes crash mid-write (requires robust boot verification/repairs).

### Content-Addressed BEAM Modules
* **Benefits**: Guarantees 100% identical representations on both nodes, allowing native Erlang continuation serialization across the cluster.
* **Trade-offs**: Dynamic module loading can bloat Erlang's atom table if not garbage collected (addressed by our LRU Code Module Purger).

---

## 4. Complexity vs. Utility

| Element | Complexity (1-10) | Utility (1-10) | Recommendation |
|---|---|---|---|
| **Genesis Primitives** | 2 | 9 | **Adopted**: Kept identity model uniform. |
| **Implicit Effects stack** | 4 | 9 | **Adopted**: Simpler runtime execution. |
| **Robust Supervisor Testing** | 2 | 8 | **Highest Actionable**: Resolve timing races via polling. |
| **Compile-time Handler Check** | 3 | 7 | **Actionable**: Enforce safety before loading bytecode. |

---

## 5. Actionable Recommendation

Implement a robust supervisor test polling logic in `gleamunison_sup` to eliminate timing race conditions. Future extensions should integrate compile-time handler validation in the compilation pipeline.
