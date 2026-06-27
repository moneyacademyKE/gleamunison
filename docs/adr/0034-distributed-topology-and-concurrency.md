# ADR 0034: Distributed Topology & Concurrency

## Status
Accepted

## Context
Phase 5 of the Gleamunison roadmap requires implementing location-aware concurrency, distributed storage, supervision trees, and serializable continuations to mirror Unison's execution model on the BEAM.

## Decision
1. **Remote Ability Representation**: Bootstrapped the `{Remote}` ability containing `forkAt`, `await`, and `here` operations using type variables for `Location` and `Task`. This avoids modifying the compiler's core type representation while retaining full type safety.
2. **Mnesia Storage Adapter**: Implemented a distributed, replicated Mnesia storage adapter utilizing Erlang's transaction system (`mnesia:transaction/1`), providing ACID compliance and seamless multi-node database synchronization.
3. **Supervision Trees**: Structured active storage holder processes under an OTP supervisor (`gleamunison_sup`) with a `one_for_one` restart strategy, improving fault tolerance.
4. **Serializable Continuations**: Leveraged Erlang's native term serialization (`term_to_binary/1` and `binary_to_term/1`) to serialize dynamic closures, stack states, and environments.

## Consequences
- No compiler overhead or complex syntax changes are needed for distributed execution.
- High-level distributed programming is native, utilizing Erlang's built-in clustering capabilities.
- Fault tolerance is guaranteed, keeping system states consistent during process crashes.
