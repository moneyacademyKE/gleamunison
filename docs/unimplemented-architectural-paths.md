# Unimplemented & Deferred Architectural Paths

This document acts as an index of advanced ideas, features, and paths proposed in various gap analyses across the `gleamunison` project that were either declined, deferred, or partially implemented, along with their engineering rationales.

---

## 1. P2P Package Registry
* **Source Document**: [gap-analysis-phase6.md](file:///Users/moe/Desktop/gleamunison_dogfood/gleamunison_repo/docs/gap-analysis-phase6.md#L37-L48) (Section 6.1)
* **Status**: **Declined / Replaced by Direct Sync**
* **Engineering Rationale**: 
  Implementing a full P2P package index requires complex decentralized discovery mechanisms (such as DHT routing or gossip protocols over TCP/UDP). Instead, the runtime leverages the direct, three-phase **Pull-Sync Networking Protocol** (`gleamunison_tcp_sync.erl` / `sync.gleam`). This allows nodes to pull any missing content-addressed definitions directly from peers using their cryptographic hashes, delivering identical integrity and security guarantees without the coordination and maintenance overhead of a decentralized index or complex DHT.

---

## 2. Evidence-Passing Compilation
* **Source Document**: [gap-analysis-koka.md](file:///Users/moe/Desktop/gleamunison_dogfood/gleamunison_repo/docs/gap-analysis-koka.md#L48-L51) (Section 4.2)
* **Status**: **Declined in favor of Process Dictionary**
* **Engineering Rationale**:
  Threading an evidence vector (handler context) through every compiled function increases compilation complexity and significantly bloats the emitted BEAM bytecode. It also complicates curried function applications and hot-reloading boundaries. Storing active ability handlers in Erlang's process dictionary (`$ability_stack`) is highly performant, fully isolated to individual BEAM processes, and preserves clean code generation.

---

## 3. Dynamic "Fill-and-Resume" Hole Execution
* **Source Document**: [gap-analysis-hazel.md](file:///Users/moe/Desktop/gleamunison_dogfood/gleamunison_repo/docs/gap-analysis-hazel.md#L42-L46) (Section 4.3)
* **Status**: **Declined in favor of Native Errors**
* **Engineering Rationale**:
  While typed holes are represented in the AST and typechecker, executing a hole currently throws a native `erlang:error({hole, incomplete_expression})` to crash the execution path. True stack-frame resumption of compiled native BEAM modules is not supported by Erlang's VM. Implementing this requires writing a custom S-expression bytecode interpreter, which would severely degrade the runtime's native performance.

---

## 4. Fully Automated Code Shipping on Closure Message Arrival
* **Source Document**: [unique_usecases_gap_analysis.md](file:///Users/moe/Desktop/gleamunison_dogfood/gleamunison_repo/docs/unique_usecases_gap_analysis.md#L48-L53) (Section 4.1)
* **Status**: **Partially Implemented (Manual Pull Required)**
* **Engineering Rationale**:
  Automatically syncing and loading unverified compiled BEAM modules from arbitrary network messages poses severe security risks (e.g., remote code execution). Consequently, dynamic code loading is designed as an **explicit operation** rather than an automated reaction; the user/runtime must intentionally invoke the pull-sync protocol (`pull_sync`) to download and verify dependency hashes prior to deserializing and running incoming closures.

---

## 5. Time-Traveling Distributed Replay Debugger
* **Source Document**: [unique_usecases_gap_analysis.md](file:///Users/moe/Desktop/gleamunison_dogfood/gleamunison_repo/docs/unique_usecases_gap_analysis.md#L26-L30) (Section 2.B)
* **Status**: **Deferred**
* **Engineering Rationale**:
  We implemented request tracing (`gleamunison_trace.erl`) to capture path/method/headers for HTTP, but a deterministic step-by-step *execution path replay* for arbitrary code with mock handler injection was deferred. Stepping through compiled BEAM bytecode requires deep VM debugging interfaces (like Erlang's `:dbg` or a custom interpreter), which introduces extreme complexity and goes against the goal of keeping the codebase small and highly cohesive (<250 LOC per file).

---

## 6. Complete LSP IDE Server
* **Source Document**: [gap-analysis-phase6.md](file:///Users/moe/Desktop/gleamunison_dogfood/gleamunison_repo/docs/gap-analysis-phase6.md#L23-L26) (Section 2)
* **Status**: **Downscoped to Diagnostics**
* **Engineering Rationale**:
  A complete LSP server handling workspace indexing, autocomplete, and hover tips requires implementing JSON-RPC stream parsers, asynchronous syntax trees, and heavy background worker architectures. To fit within code limits, LSP integration was downscoped to a parser-phase compile error diagnostics reporter, letting standard editors highlight syntax and parse errors without full protocol overhead.

---

## 7. Show Ability with Pretty-Printed Surface S-Expressions
* **Source Document**: [gap-analysis-low-complexity.md](file:///Users/moe/Desktop/gleamunison_dogfood/gleamunison_repo/docs/gap-analysis-low-complexity.md#L14) (Section 1)
* **Status**: **Declined**
* **Engineering Rationale**:
  The `Show` ability was mapped directly to Erlang's `io_lib:format("~p", [Val])`, which formats terms using their native BEAM representations (tuples and lists). Formatting terms back into Unison surface S-expressions requires mapping constructor names and structural layout recursively back to text strings, which would double the size of the FFI layer and introduce runtime decoding overhead.
