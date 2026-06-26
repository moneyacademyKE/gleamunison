# Gap Analysis: gleamdb as Storage Backend

Analysis of using `moneyacademyke/gleamdb` (aarondb) as the storage backend
for the gleamunison codebase.

---

## What gleamdb (aarondb) is

A Datalog engine for the BEAM written in Gleam. Key characteristics:

- **Data model**: EAV (Entity-Attribute-Value) triples stored as Facts/Datoms
- **Storage adapters**: pluggable via `StorageAdapter` record (insert, append,
  read, read_all, query_datoms)
- **Backends**: ephemeral (ETS), distributed (Mnesia), consensus (Raft)
- **Query engine**: full Datalog with rules, pull patterns, bitemporal queries
- **Transactions**: assert/retract with transaction time tracking
- **Reactive**: subscribe to query results, WAL subscriptions
- **Distributed**: named databases via Erlang global, Raft consensus

```gleam
// Core data model
pub type Fact = #(Operation, Eid, Attribute, Value)
pub type Datom = Fact + transaction metadata (tx, added?, valid_time)

// Storage adapter interface
pub type StorageAdapter {
  StorageAdapter(
    insert: fn(List(Datom)) -> Result(Nil, StorageError),
    append: fn(List(Datom)) -> Result(Nil, StorageError),
    read: fn(String) -> Result(List(Datom), StorageError),
    read_all: fn() -> Result(List(Datom), StorageError),
    query_datoms: fn(Clause) -> Result(List(Datom), StorageError),
  )
}
```

---

## What our Codebase needs

From `codebase.gleam`:

```gleam
pub opaque type Codebase {
  Codebase(
    defs: Map(DefinitionRef, Definition),       // primary: Ref → Definition
    computed_types: Map(DefinitionRef, ComputedType), // secondary index
    meta: Map(DefinitionRef, Metadata),          // secondary index
    seen: Map(Hash, DefinitionRef),              // hash → ref lookup
    roots: Set(DefinitionRef),                   // root set
    backend: StorageBackend,                     // pluggable
  )
}
```

Core operations:
1. **Lookup by hash**: `DefinitionRef → Definition` (the critical path)
2. **Hash dedup**: `Hash → DefinitionRef` (seen set)
3. **Type lookup**: `DefinitionRef → ComputedType`
4. **Root management**: add/query root refs
5. **Metadata**: `DefinitionRef → Metadata` (source locs, docs)
6. **Hash verification**: re-hash definition on insert, reject mismatch
7. **Dependency queries**: "what depends on Ref(#X)?"

---

## Gap 1: Data model mismatch — EAV triples vs structured records

**What gleamdb stores:** Facts are `#(Operation, Eid, Attribute, Value)`. A
`Value` is an enum of `Int | Float | Str | Ref | Bytes | ...`. To store a
`Definition` (a rich Gleam record with `Term`, `Type`, etc.), we must:
1. Serialize it to bytes (bit_array)
2. Store as multiple facts per definition
3. Reconstruct on read

**What we need:** `DefinitionRef → Definition` — a single atomic read/write.
The Definition is opaque bytes from the perspective of storage.

**The complection:** gleamdb's EAV model is designed for *queryable* data
where you ask "find all entities with attribute X = value Y." Our definitions
are opaque, hash-verified blobs. We don't need to query inside them. The
EAV decomposition adds serialization overhead with no benefit.

**Verdict:** Mismatch. gleamdb's strength (structured queryable facts) is
irrelevant to our primary use case (opaque key-value lookup).

---

## Gap 2: Merkle verification doesn't exist in gleamdb

**What gleamdb provides:** `insert(datoms)` stores facts. There is no hash
verification, no concept of a "Merkle DAG," no integrity checking.

**What we need:** Every insert must:
1. Compute `hash_of_definition(def)` (includes both term and type)
2. Compare against the claimed `DefinitionRef`
3. Reject on mismatch: `HashMismatch(hash_expected, hash_got)`

**The complection:** We would need to wrap every gleamdb insert with hash
verification logic in our codebase module. gleamdb cannot enforce this
invariant itself — it doesn't know about hashes. The invariant lives in
our application layer, not the storage layer.

**Verdict:** Manageable — we'd do verification before calling gleamdb.
But it means gleamdb is just a dumb store, not adding semantic value.

---

## Gap 3: gleamdb's StorageAdapter abstraction aligns with our StorageBackend

**Our current spec:**
```gleam
pub type StorageBackend {
  InMemory
  DETS
  SQLite
}
```

**gleamdb's approach:**
```gleam
pub type StorageAdapter {
  StorageAdapter(
    insert: fn(List(Datom)) -> Result(Nil, StorageError),
    append: fn(List(Datom)) -> Result(Nil, StorageError),
    read: fn(String) -> Result(List(Datom), StorageError),
    read_all: fn() -> Result(List(Datom), StorageError),
    query_datoms: fn(Clause) -> Result(List(Datom), StorageError),
  )
}
```

**Analysis:** gleamdb already has the pluggable storage adapter pattern we
want. Its backends (ETS, Mnesia, Raft) map well to our needs:
- Ephemeral → InMemory (prototype)
- Mnesia → distributed durable (production single-cluster)
- Raft → consensus-based (production multi-cluster)

But: gleamdb's adapter operates on `List(Datom)`, not on our `Definition`
type. We'd write a translation layer.

**Verdict:** The pattern is right. The interface is wrong for our types.

---

## Gap 4: bitemporal queries are overkill but could be useful

**What gleamdb provides:** `as_of(tx)` queries, valid time, transaction time.
Full bitemporal data model.

**What we need:** The gap analysis vs Unison (Gap 5) identified "append-only
event log" as a future need. Bitemporal would give us time-travel debugging
and rollback — matching Unison's codebase-as-event-log.

**Analysis:** If we store each definition insertion as a fact with
transaction time, gleamdb automatically gives us:
- History: "what was Ref(#X) at transaction 42?"
- Audit: "when was this definition added?"
- Rollback: "restore the codebase to transaction 50"

This is valuable. But it's a future concern, not a current requirement.

**Verdict:** Nice-to-have. Not worth the complexity cost today.

---

## Gap 5: Distributed backends (Mnesia, Raft) match our Sync module

**What gleamdb provides:** `start_distributed(name, adapter)` — registers
a database globally via Erlang's global process registry. Raft backend for
consensus.

**What we have:** A `Sync` module that exchanges roots and Units between
nodes via a pull-based protocol.

**Analysis:** gleamdb's distributed backends would let multiple gleamunison
nodes share a codebase directly via Mnesia or Raft, eliminating the need
for our custom `Sync` protocol. The codebase becomes a shared database
rather than a replicated set of definitions.

This is a fundamentally different distribution model:
- **Our model** (pull-based Merkle sync): Each node has its own codebase.
  They exchange roots and pull missing definitions. Works over any transport.
- **gleamdb model** (shared database): All nodes read/write the same
  codebase via Mnesia/Raft. Strong consistency. Requires cluster membership.

**The trade-off:** Shared database is simpler (no sync protocol) but couples
nodes tightly (same cluster, same database). Merkle sync is more loosely
coupled (works over HTTP, across clusters, with intermittent connectivity).

**Verdict:** Different models for different deployment scenarios. Both are
valid. Our `StorageBackend` could support both: InMemory/DETS for standalone,
Mnesia for shared-database clusters, and our custom Sync for loose coupling.

---

## Gap 6: Dependency tracking — Datalog would excel here

**What we currently have:** `dependents(codebase, ref) -> List(DefinitionRef)`
— a `todo` function with unspecified implementation.

**What gleamdb enables:** A Datalog query like:
```clojure
(defn depends-on [?def ?dep]
  (where [?def :definition/term ?term]
         (term-contains-ref ?term ?dep)))
```

But this requires storing the term AST as queryable EAV facts, not as
opaque bytes. Storing the term as facts means every AST node becomes
multiple facts — massive storage overhead and write complexity.

**Verdict:** Datalog queries into definition structure is powerful but
requires decomposing our AST into EAV form. That's a separate project
(an AST-indexing layer), not a storage backend concern.

---

## Gap 7: Reactive subscriptions could replace the Loader polling model

**What gleamdb provides:** `subscribe(db, query, subject)` — pushes results
to a process when matching facts change. `subscribe_wal(db, subject)` —
pushes raw datoms for all changes.

**What we have:** The Loader currently watches the Codebase by polling or
by being called after insertion (Syncer → Codebase → Loader pipeline).

**Analysis:** With gleamdb's WAL subscriptions, the Loader could be notified
immediately when new definitions are inserted. No polling, no pipeline
coupling. The Codebase pushes to the Loader.

**Verdict:** A genuine benefit, but achievable with a simple
`erlang:monitor/2` or `Subject` pattern without adopting a full Datalog
engine. The reactive model is good; the dependency on Datalog to get it
is not.

---

## Summary

| Concern | Benefit of gleamdb | Cost | Verdict |
|---|---|---|---|
| **Key-value storage** | None — Datalog is the wrong model | Serialization overhead | **Negative** — our data is opaque blobs, not queryable facts |
| **Hash verification** | None — gleamdb doesn't know about hashes | Must implement in our layer | Neutral |
| **Backend pluggability** | Already has the pattern | Wrong interface (Datoms vs Definition) | **Close but misaligned** |
| **Bitemporal** | Time travel, audit | Not needed yet | Premature |
| **Distribution** | Mnesia/Raft for shared codebase | Tighter coupling, cluster requirement | **Alternative model**, not a replacement |
| **Dependency queries** | Datalog excels here | Requires decomposing AST into EAV | Too expensive for current needs |
| **Reactive loading** | WAL subscriptions | Achievable without Datalog | Benefit exists, dependency not justified |
| **Dependency weight** | — | Raft, Mnesia, HTTP server, Lustre UI, JSON, crypto, etc. | **Heavy** — pulls in 10+ dependencies |

---

## Recommendation

**Don't use gleamdb as the storage backend for the codebase.**

The data model mismatch is fundamental:
- gleamdb stores *queryable facts* (EAV triples)
- Our codebase stores *opaque, hash-verified blobs* keyed by hash

Adopting gleamdb means:
1. Serializing/deserializing every Definition to/from EAV facts
2. Implementing hash verification in our layer anyway
3. Pulling in a Datalog query engine, Raft consensus, HTTP server, Lustre UI,
   and other dependencies we don't need for storage
4. Still needing to write the Merkle verification and definition store logic

**What to do instead:**

Keep our `StorageBackend` abstraction but change the implementation strategy:

1. **Replace `StorageBackend` with gleamdb's `StorageAdapter` interface** —
   Borrow the pattern (pluggable backend via function record) but with our
   types (Definition, not Datom)

2. **For InMemory prototype**: Use Gleam's `Dict` (already done)

3. **For DETS production**: Use the Erlang `dets` module directly via FFI —
   it's a key-value store, perfect for `Ref → Bytes`

4. **For distributed production**: Two options:
   a. Use gleamdb's Mnesia/Raft backends as the *transport*, but store
      serialized Definitions as the *value* (not EAV facts)
   b. Use our custom Sync protocol for loose coupling

5. **For dependency tracking**: Add an explicit `deps: Set(DefinitionRef)`
   field to the Definition or Unit — Datalog queries are overkill when
   dependencies are known at insertion time

The right tool for our storage is a **content-addressed key-value store**
(hash → blob), not a Datalog engine. gleamdb would be useful as a *separate*
service for querying definition metadata (source locations, dependency
graphs, etc.), but not as the primary codebase store.

---

## Resolution

The following changes were made based on this analysis:

| Recommendation | Status | Implementation |
|---|---|---|
| **1. Replace StorageBackend enum with StorageAdapter function-record** | **COMPLETED** | `codebase.gleam` v3: `StorageAdapter` with 6 functions operating on `BitArray`. ADR-0010 documents the pattern. |
| **2. InMemory prototype** | **COMPLETED** | `inmemory()` factory function provided (wraps Gleam Dict). |
| **3. DETS production** | Spec'd | `dets(path)` factory function signature defined, implementation is a `todo`. |
| **4. Distribution options** | Deferred | Mnesia/Raft adapters documented but not required for prototype. Custom Sync protocol is the primary distribution mechanism. |
| **5. Dependency tracking** | **COMPLETED** | `dependencies(def)` and `dependents(codebase, ref)` functions added. Dependencies computed from AST, not stored explicitly. |
