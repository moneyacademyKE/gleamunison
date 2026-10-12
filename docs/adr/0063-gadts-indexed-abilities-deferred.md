# ADR-0063: GADTs and Indexed Abilities — Deferred, with a Tripwire

## Context

Unison 1.5.0 (2026-10-02) shipped GADTs and GADT-indexed abilities — ability
operations whose result types are indexed by a type-level state, letting the
type system track protocol phases (a connection is `Open` or `Closed`, and
`read` is only callable on `Open`). The gap analysis
(`docs/gap-analysis-v3.12.0-unison-v1.5.0.md`) flagged this as the one real
language gap between gleamunison and Unison.

GleamUnison's type system is Hindley–Milner over plain ADTs
(`src/gleamunison/inference.gleam`), and ability rows are runtime handler
stacks with inferred `Requirement` metadata (ADR index: effect requirements
landed in v3.15.0). Expressing GADTs requires three things HM does not have:

1. **Type-level equality constraints.** A GADT constructor like
   `Read : Ability (Open s) (Result s)` carries `s ~ Open` inside its
   result. Unification must solve existentials and equalities, not just
   variables.
2. **Indexed type constructors.** Type constructors take type arguments
   that participate in matching (`Ability phase result`), which our
   structural `ast.Type` cannot represent — constructor application is
   not first-class in the type language.
3. **Refinement on match.** `case` on a GADT constructor refines type
   variables in the branch. Our match elaboration binds names; it does
   not narrow types.

## Decision

**Defer. Do not build GADTs now.** The tripwire below defines when to
revisit.

### Why defer (the cost side, concretely)

- The change is an HM-core rewrite: unification gains equality constraints,
  the type language gains indexed constructors, match elaboration gains
  refinement, and the pretty-printer, the requirement inference, and the
  hash function all change shape. Estimate: touches inference.gleam,
  ast.gleam, elab_term.gleam, elab_def.gleam, type_pretty.gleam — the
  densest modules in the repo — for a feature with zero current users.
- Every alternative we actually need today is already expressible:
  protocol-state tracking is a handler concern (the transcript system
  already records and replays op sequences), and evidence attestation
  already separates "what ran" from "what the type claims."
- Unison shipped GADTs in 1.5.0 and, as of this writing, no widely-used
  Unison library requires them. We would be building against a moving,
  unproven target.

### The tripwire

Revisit when **either** fires:

1. A Unison library we want parity with (HTTP client, DB driver, parser
   combinator) ships an API that *requires* indexed abilities — not as
   decoration but as the only way to express the contract.
2. We hit a real protocol bug in gleamunison that a type-indexed ability
   would have caught at elaboration time and the handler layer cannot
   catch at runtime (the replay/capability systems already catch op-level
   drift; the tripwire is a bug class they structurally miss).

### Safe preparatory seams (already in place, or cheap now)

These are not GADT work — they are general robustness that happens to
remove the biggest landmines from a future GADT path:

- **Spans in elaboration errors** (v3.15.0): any type-system surgery
  produces worse error messages before it produces better ones; located
  errors are the safety net.
- **Effect requirement inference** (v3.15.0): `ast.Fn` already carries a
  `Requirement`; indexed abilities would extend this row, so the seam is
  proven to flow through inference end-to-end.
- **Alpha-canonical hashing** (proved by regression tests in v3.15.0):
  GADT constructors would change hash inputs; canonical identity means
  that change is isolated to the hash function, not the DAG.

## Consequences

- The HM core stays simple and the error messages stay readable — the two
  properties that make the language teachable to agents and humans alike.
- The deferral is a decision, not drift: the tripwire is written down, and
  the preparatory seams mean the eventual implementation starts from
  infrastructure, not from scratch.
- If the tripwire never fires, we never pay the cost. If it fires, we pay
  it with spans, requirement rows, and canonical hashing already in place.
