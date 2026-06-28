# Gap Analysis: Transient vs Supervised ETS Table Ownership

A Rich Hickey-style analysis of ETS table lifetime management in Erlang/BEAM as applied to the Gleamunison peer synchronization protocol.

---

## 1. Feature Set Comparison

| Capability | Ephemeral/Transient Creation | Supervised Background Holder |
|---|---|---|
| **Table Owner** | Short-lived process (e.g., RPC handler) | Long-lived supervised process (`ets_holder`) |
| **Data Persistence** | Lost when caller process terminates | Retained across caller process Lifecycles |
| **Concurrency Safety** | Thread-local or temporary | Public concurrent reads/writes |
| **Initialization Cost** | Repeated `ets:new` calls | Single initialization at startup |
| **Complexity** | High (flaky error recovery logic) | Low (declarative table creation) |

---

## 2. Explanation of Differences

* **Table Owner**: In Erlang, every ETS table is owned by the process that created it. Ephemeral processes (like transient RPC connections) exit immediately after execution, automatically destroying their tables. Supervised worker processes persist indefinitely.
* **Data Persistence**: Supervised tables survive client process crashes and exits. ephemerally-owned tables suffer from silent deletions, throwing `badarg` errors on subsequent attempts to query the table.
* **Initialization Cost**: Ephemeral tables check for presence and recreate on-demand, which leads to race conditions. Supervised tables are created once at boot.

---

## 3. Benefits and Trade-offs

### Ephemeral Table Creation
* **Benefits**: Creates tables on-demand; no need to declare tables at supervisor initialization.
* **Trade-offs**: Causes data loss in multi-process/RPC environments; transient processes exit and reclaim the tables.

### Supervised background process
* **Benefits**: Table persists across VM connections and parallel queries; aligns with ADR-0017 design invariants.
* **Trade-offs**: Slightly increased supervisor initialization setup.

---

## 4. Complexity vs. Utility

| Element | Complexity (1-10) | Utility (1-10) | Recommendation |
|---|---|---|---|
| **Supervised ets_holder** | 2 | 10 | **Highest Actionable**: Ensure all shared tables are owned by long-lived workers. |
| **Ephemeral on-demand check** | 3 | 2 | **Avoid**: Fragile and leads to silent data loss under concurrency. |

---

## 5. Actionable Recommendation

Refactor `gleamunison_sup.erl` to register the `gleamunison_peer_refs` table under the supervised `ets_holder` worker process on startup. Simplify `gleamunison_ffi_io.erl` to perform direct inserts into the persistent table.
