# ADR 0069: Durable application data through one Db ability

- **Status:** Accepted
- **Date:** 2026-10-26 (EAT)
- **Tracking:** Bankai `bk-2a5c`
- **Related:** [ADR 0001](0001-content-addressed-identity.md), [ADR 0062](0062-native-content-addressed-datalog-database.md), [ADR 0067](0067-production-boundaries.md), [ADR 0068](0068-durable-agent-read-model.md)

## Context

The definition store is immutable, content-addressed code and evidence. The
Datalog engine supplies immutable EAV indexes, transactions, and an in-process
transactor model, but its values do not automatically become durable application
state. Ordinary published definitions also need one typed effect boundary
rather than a second mutable namespace or an ambient file-write backdoor.

The first contract must stay smaller than a general database server. Text-valued
EAV facts and exact reads are enough to prove admission, atomic commit,
retraction, and restart persistence without expanding the surface type system or
embedding an interpreter in every effect call.

## Decision

1. **One ability, three operations.** `Db.transact(assertions, retractions)`
   returns a monotonically increasing transaction id. `Db.get(entity, attribute)`
   returns the current facts for an exact entity/attribute pair.
   `Db.find(attribute, value)` returns exact attribute/value matches. A fact is
   `(pair entity (pair attribute text-value))`; assertions and retractions are
   lists of facts. Retractions are applied before assertions within one batch.
2. **Effect admission is shared.** `Db` is a bootstrap ability with concrete
   argument and result types. The inference checker validates operation
   arguments, not just the operation's output. `Do Db ...` is effectful for
   publication and execution evidence, and the existing capability frame can
   deny it before its handler runs.
3. **Application data is not code CAS.** A supervised `gleamunison_app_db`
   owner writes `application.dets` beside the configured code store. Each
   transaction is one journal record committed with one DETS insert and sync.
   The current EAV map is derived by replaying committed journal records after
   restart; it is not a second durable truth. A malformed batch is refused
   before the journal write.
4. **Reuse the model, not a second interpreter.** The owner follows the
   existing Datalog EAV/transaction vocabulary and exact `db-find` shape. The
   pure fact module handles validation, replay, and reads. Arbitrary joins,
   schema evolution, temporal queries, and an HTTP database API are explicitly
   outside this milestone.
5. **Capability denial is not host isolation.** The default local evaluator
   installs the `Db` frame. `untrusted-execution` remains governed by ADR 0067:
   it is refused without an approved external OS/container executor and is not
   declared safe by this in-process frame. `file-read` and `http-get` remain
   separate host capabilities; there is no ordinary ambient application-data
   write or HTTP write primitive. They must not be advertised as a way around
   the `Db` boundary.

## Consequences

- A published definition can read and write application facts through the
  same runtime effect stack as other abilities.
- A restarted owner recovers the current facts and the next transaction id;
  code content and application state have independent lifecycles.
- Read-only agent/store surfaces do not silently create or mutate application
  state. The application owner starts on first `Db` use.
- V1 is intentionally an exact-match EAV store, not a claim of full Datalog
  query or multi-node database support. Future query work must preserve this
  journal and capability boundary rather than introduce a parallel database.

## Alternatives rejected

- **Persist the in-memory Datalog engine directly:** rejected for this slice;
  it would require serializing arbitrary runtime values and make every effect
  depend on re-evaluating a second language runtime.
- **Put application writes in definition CAS:** rejected; mutable application
  facts are not immutable definitions or evidence.
- **Expose `Db` as an untyped host-value bag:** rejected; the factory needs a
  typed effect signature and checked arguments before admission.
- **Call the frame a sandbox:** rejected; a process handler cannot provide OS
  isolation, filesystem secrecy, or network policy by itself.

**Rich Hickey check:** one effect, one journal, one owner, and pure fact
transformations composed around them. The rejected designs complect code with
state, durability with presentation, and a capability check with an isolation
boundary.
