# ADR-0007: Pull-based node synchronization

**Status:** Accepted

**Date:** 2026-06-26

## Context

Multiple gleamunison nodes running on a BEAM cluster need to share definitions.
The sync mechanism must handle:
- Nodes joining and leaving arbitrarily
- Definitions arriving on any node at any time
- Verification (the data received is what was requested)
- Minimal coordination overhead

Two approaches: push (sender decides what the receiver needs) and pull
(receiver computes the diff and requests what's missing).

## Decision

Pull-based synchronization with Merkle root exchange:

1. Nodes exchange their root hashes (the `DefinitionRef`s at the top of
   their namespace trees)
2. Each node computes the set of hashes it doesn't have locally
3. The deficient node requests `Unit`s for those roots
4. The responding node sends `Unit`s (root + all transitive deps)
5. Each definition in the `Unit` is verified by hashing before insertion

Messages:
- `Hello(node, version)` — handshake
- `Roots(hashes)` — "these are the refs I know about"
- `RequestDeps(roots)` — "send me Units for these"
- `UnitResponse(units)` — "here are the requested Units"
- `MissingRefs(refs)` — "I don't have those"
- `Ping(timestamp)` — heartbeat

## Consequences

**Positive:**
- Stateless exchange: the sender doesn't need to know the receiver's state.
  It just sends its roots. The receiver computes the diff locally
- Verification is local: hash each received definition against its claimed
  `DefinitionRef`. No cross-node trust required
- Content-addressing makes this natural: the same hash means the same thing
  on every node, so there's no confusion about what's being requested
- No conflicts possible: the codebase is append-only. Two nodes inserting
  the same definition is idempotent
- Gossip is simple: each node periodically broadcasts its roots. No vector
  clocks, no CRDTs, no causality tracking

**Negative:**
- Latency: a node must wait for the gossip interval to learn about new roots
  (but this can be reduced by piggybacking root updates on application messages)
- Bandwidth for large codebases: root set grows with number of roots (but
  roots are just 32-byte hashes, so 10,000 roots = 320KB)
- Initial sync: a new node starting with an empty codebase must download
  all roots from its peers (but this is a one-time cost)

**Comparison to push:** Push requires the sender to track what each peer
already has — a distributed state problem. Push is appropriate for
notifications (new content available) but not for content transfer. Our
approach: push notifications + pull content transfer.
