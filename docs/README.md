# Documentation index

Start here. The repository has current references, historical analysis, and
verification evidence; those are different kinds of documents and should not
make the same claims.

## Start with the runtime

| Document | Use it for |
|---|---|
| [Project README](../README.md) | Current capabilities, quick start, CLI, and production boundaries |
| [Contributing](../CONTRIBUTING.md) | Toolchain, change workflow, and verification |
| [Repository agent guide](../AGENTS.md) | Concise source map and working agreements |
| [Reference manual](MANUAL.md) | Language, CLI, storage, agent, Db, and HTTP surfaces |
| [Architecture](ARCHITECTURE.md) | Current identity, admission, state, service, and trust composition |
| [Glossary](GLOSSARY.md) | Current project vocabulary |
| [Roadmap](ROADMAP.md) | Verified baseline, real exclusions, and candidate next increments |
| [Playbook](PLAYBOOK.md) | Development and conformance methodology |
| [Scripts](../scripts/README.md) | Exact verification and development script entry points |

## Build and operate

- [Build Escript](BUILD_ESCRIPT.md) — artifact contents, build, and release checks.
- [Operations](OPERATIONS.md) — single-node setup, configuration, backup, and recovery.
- [Deployment profiles](operations/deployment-profiles.md) — implemented bind,
  token, sync, and execution-profile boundaries.
- [Compatibility](operations/compatibility.md) — toolchain and codec contracts.
- [Observability](operations/observability.md) — bounded metrics, logs, traces,
  readiness, and drain.
- [Trust and key rotation](operations/trust-and-key-rotation.md) — configured
  signer and library-only overlap behavior.
- [LLM policy](operations/llm-policy.md) — budgets, cancellation, and redaction.
- [Upgrade and rollback](operations/upgrade-and-rollback.md) — artifact identity,
  drain, compatibility, and recovery.
- [Verification matrix](operations/verification-matrix.md) — boundary-to-proof map.
- [LSP](LSP.md) — language-server transport and features.

## Factory decision trail

Read these together when changing the agent/application path:

1. [ADR 0065 — verified CAS admission](adr/0065-verified-cas-admission.md)
2. [ADR 0067 — production boundaries](adr/0067-production-boundaries.md)
3. [ADR 0068 — durable agent read model](adr/0068-durable-agent-read-model.md)
4. [ADR 0069 — durable Db ability](adr/0069-durable-db-ability.md)
5. [ADR 0070 — admitted agent writes](adr/0070-admitted-agent-writes.md)
6. [ADR 0071 — admitted app routes](adr/0071-admitted-app-routes.md)
7. [ADR 0072 — bounded agent generation](adr/0072-bounded-agent-generation.md)
8. [ADR 0073 — target-selected helper generation](adr/0073-target-selected-helper-generation.md)

The [ADR index](adr/README.md) contains the complete decision history. An
accepted decision is not by itself evidence that all of its proposed steps are
implemented. Current source and later implementation notes decide that.

## Verification evidence

Dated documents are point-in-time receipts. Do not repaint them with newer
numbers; add a new witness for a new verified tree.

- [Factory readiness — 2026-10-26](verification/factory-readiness-2026-10-26.md)
- [Bounded agent generation — 2026-10-26](verification/bounded-agent-generation-2026-10-26.md)
- [Production-boundary witness — 2026-10-26](verification/production-boundaries-2026-10-26.md)
- [Production-boundary witness — 2026-10-27](verification/production-boundaries-2026-10-27.md)
- [Run identity proofs](verification/run-identity-proofs.md)
- [Audits](audit/) — findings and reproductions at their recorded revisions.
- [Plans](plans/) — implementation plans and walkthroughs for specific changes.

The latest production witness reports 740 local tests passing and the
target-selected helper generation loop at `d36f32e`; that is evidence for that
revision, not a permanent suite counter. Hosted CI results are separate
evidence.

## Language and implementation notes

These documents answer focused questions; they are not an alternative runtime
manual:

- [Hashing](hashing.md) — canonical term/type identity and payload verification.
- [Genesis modules](genesis-modules.md) — native builtin implementations and
  bootstrap wiring.
- [Monadic `chain`](MONADS.md) — continuation/lambda-passing idiom.

## Historical material

The following remain useful for rationale, rejected alternatives, and prior
experiments. They may contain old counts, deleted modules, or proposals that
never shipped. Do not use them as current setup instructions without checking
source and the relevant ADR.

- [Learnings](LEARNINGS.md) and [Patterns](PATTERNS.md) — historical engineering
  notebooks, now labeled as such.
- `gap-analysis-*.md`, [unique use-cases analysis](unique_usecases_gap_analysis.md),
  and [low-complexity analysis](gap-analysis-low-complexity.md) — comparative
  and exploratory analysis.
- [Dogfood loop](DOGFOOD_LOOP.md) and [old roadmap items](ROADMAP_ITEMS.md) —
  earlier generator/loop methodology and completed improvement lists.
- [Unimplemented architectural paths](unimplemented-architectural-paths.md) —
  rejected/deferred ideas, not a hidden feature inventory.
- [Run-maturity walkthrough](walkthrough-run-maturity.md) — point-in-time change
  walkthrough.
- [Archive](archive/README.md) — superseded analyses and walkthroughs retained
  with their original paths.
- [Changelog](../CHANGELOG.md) — release history, not a source of current
  verification status.

No historical files were moved in this cleanup, so existing inbound links and
provenance remain intact.

## Documentation maintenance rule

Keep durable contracts in the current guides, decisions in ADRs, and measured
counts/artifact hashes/command results in dated witnesses. When one of these
changes, update its owner rather than copying a new claim across every file.
Before citing a module, command, flag, or test filename, check that it exists in
the current tree.
