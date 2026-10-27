# Roadmap

## Current baseline

Gleamunison v3.24.0 has a verified **local, authenticated, single-node factory
loop**: bounded MCP generation → signed admitted definition → durable Db write
→ supervised Db-owner restart → HTTP `/app` read.

The acceptance evidence is
[Factory readiness — 2026-10-26](verification/factory-readiness-2026-10-26.md),
with the machine-readable gate results in the matching production witness.
Those dated documents own counts, artifact hashes, environment details, and
exclusions. This roadmap owns remaining design scope, not a claim that future
work is implemented.

Old phase-by-phase implementation history remains in git and in the ADR/audit
record. It is not repeated here as a list of current capabilities.

## Explicit current boundaries

These are not unfinished documentation; they are real product boundaries:

- No OS/container isolation for hostile code. `untrusted-execution` refuses
  transport-facing work without an approved external executor.
- No native HTTP TLS/mTLS. Remote transport protection is an external operator
  responsibility; the startup gate cannot verify a proxy or certificate.
- No supported multi-node production topology or multi-tenant isolation claim.
- No live process migration or general serializable-continuation implementation.
- No complete package identity/revocation system beyond the current evidence
  and manifest policy.
- No external-provider quality benchmark. Repository generation acceptance uses
  deterministic/local provider fixtures and proves runtime composition, not
  model intelligence.
- Playbook exclusions remain exclusions, not passing conformance.

## Candidate next increments

Each item needs its own ADR/specification, regression-first implementation,
and verification evidence before its status changes. Ordering here expresses
dependency, not a delivery date.

### 1. Richer admitted generation

**Goal:** compose useful applications without weakening admission.

Implemented slice: explicit target-selected helper requests and receipts. An
optional `target` names the definition that owns the requested signature; that
candidate may include admitted helper definitions and reports real content
refs. See [ADR 0073](adr/0073-target-selected-helper-generation.md) and the
[2026-10-27 production witness](verification/production-boundaries-2026-10-27.md).

Remaining potential scope:

- Schema vocabulary beyond the current scalar/list and scalar-function subset.
- Dependency-aware patch application without inventing stored source.
- Semantic evaluation fixtures beyond “the candidate passed its own tests.”
- Reachability constraints for helper bundles, rather than explicit bundle
  admission alone.

Entry constraints: one publication authority; bounded attempts/input/output;
server-owned provider configuration; inferred-type checks; unchanged branches
on exhaustion; exact-hash evidence for effectful definitions.

### 2. Application Db queries and lifecycle

**Goal:** grow the durable application model without turning it into a second
code namespace or an untyped host-value bag.

Potential scope:

- Compositional query/read operations over the existing journal.
- Explicit schema evolution and migration proofs.
- Backup/restore fixtures covering code and application state together.
- More application acceptance examples using generated code.

Entry constraints: preserve the typed effect boundary, one journal authority,
atomic transactions, restart recovery, and separation from the self-hosted
Datalog engine's in-process model.

### 3. Remote-service hardening

**Goal:** make the operational transport contract verifiable rather than assumed.

Potential scope:

- A documented and testable trusted-proxy identity contract, or native TLS in
  a separately reviewed design.
- Sync/distribution exposure guidance and executable refusal probes.
- Durable/exported operational observability where an operator needs it.
- Recovery drills against the actual deployed artifact/configuration.

Entry constraints: request authentication is not transport encryption; a token
is not a proxy identity; an authenticated request is not permission to execute
hostile code.

### 4. External untrusted executor

**Goal:** evaluate hostile code outside the trusted BEAM/host process.

Required design evidence:

- Executor identity and approved configuration.
- Filesystem, network, kernel/process, and descendant isolation.
- CPU/memory/reduction/concurrency limits and cancellation.
- Secret redaction and cleanup proof after timeout/crash.
- End-to-end refusal when any required control is absent.

Entry constraint: an in-process ability handler or supervisor is not the
executor. Do not relabel `authenticated-remote` as a sandbox while this work
is absent.

### 5. Distribution and migration

**Goal:** define a supported topology only after identity, storage, transport,
and recovery semantics are designed together.

Potential scope: branch convergence, application-state ownership, cluster
authentication/encryption, schema migration, rollback, and process/continuation
migration if independently justified.

Entry constraint: Mnesia adapter availability, TCP sync, and hash-named modules
do not by themselves constitute a safe distributed production platform.

## Working rule for roadmap changes

A roadmap item becomes “implemented” only with source, tests, current-guide
updates, and dated evidence. A design or accepted ADR remains a design until
those exist. Do not backfill old release tables with new counts or mark an item
complete because a same-named data type exists.

The preferred increment is the smallest one that composes existing identity,
evidence, storage, effect, and service contracts. A parallel write path,
ambient storage authority, or sandbox-shaped flag is complexity, not progress.
