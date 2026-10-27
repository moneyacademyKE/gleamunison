# ADR 0073: Target-selected helper generation

- **Status:** Accepted
- **Date:** 2026-10-27 (EAT)
- **Tracking:** Bankai `bk-da31`
- **Implementation:** pending
- **Related:** [ADR 0072](0072-bounded-agent-generation.md), [ADR 0070](0070-admitted-agent-writes.md), [ADR 0068](0068-durable-agent-read-model.md)

## Context

ADR 0072 deliberately limited one generation attempt to one non-test target
term. The underlying publication path already elaborates, tests, attests, and
admits several definitions, but signature-constrained generation rejects a
candidate with helpers because it has no way to identify which definition owns
the requested signature.

Useful generated applications need local helpers. Admitting a bundle and
accepting whichever definition happens to have the requested type would be
ambiguous. Requiring one RPC per helper would let callers construct the same
bundle through more orchestration while adding partial-application states and
retry complexity.

### Gap analysis

| Option | Power added | Reason and trade-off |
|---|---|---|
| Keep single-term generation | None | Simple, but leaves the roadmap's helper gap open. |
| Accept any matching definition | Ambiguous bundle admission | A helper with the same type can impersonate the target; rejection order becomes semantics. |
| Infer the target from its name or source order | Implicit convention | Model output and parser ordering become hidden API contracts. |
| Require an explicit target | Deterministic helper composition | One optional input makes signature ownership and receipts unambiguous. |
| Publish helpers in separate RPCs | No bundle contract | More attempts and partial states without new admission power. |

### Complexity versus utility

| Complexity | Utility test | Verdict |
|---|---|---|
| Optional target in the typed plan and MCP schema | Names exactly one existing publication subject for the established inferred-type check | Keep; small data addition. |
| Target field in the generation receipt | Composes with the existing definition list to distinguish target from helpers | Keep; no duplicated refs. |
| Dependency-closure proof for every helper | Would require a new graph policy before the first helper use case | Defer; current request explicitly admits the supplied bundle. |
| New multi-definition publisher | Duplicates the authority that already admits bundles | Reject. |

The weighted recommendation favors **admission correctness and compatibility
over orchestration convenience**: explicit target selection adds the needed
power without changing storage, evidence, branch, or provider authority.

## Decision

1. **Target selection is explicit and optional.** `agent_generate` accepts a
   non-empty `target` string in addition to the existing fields. The typed
   generation plan carries `Option(String)`. Omitting it preserves ADR 0072's
   single-term behavior exactly.
2. **A target opts into bundle generation.** The candidate may define the
   named target, helper terms, and their tests. The prompt states this contract;
   the SAP envelope remains exactly `source` and `signature`.
3. **The named target owns the requested signature.** Before evidence or
   admission, publication finds that exact non-test subject and compares its
   inferred type with the requested schema. A missing target or mismatched type
   rejects the attempt. Legacy requests still require exactly one subject.
4. **There is still one publication authority.** Target-selected generation
   extends the existing `agent_publish` composition and reuses source loading,
   elaboration, tests, signed evidence, the turnstile, CAS, and selected-branch
   binding. It adds no direct storage route.
5. **Receipts compose existing data.** Generation reports the requested target
   name and retains the publication's complete definition/content-ref list.
   The target identifies its entry; the other entries are admitted helpers.
   Legacy generation reports a null target rather than inventing a name.
6. **Existing boundaries remain unchanged.** Attempts, prompt bytes, completion
   bytes, and source bytes keep their limits. Rejection and exhaustion do not
   create new branch bindings; the immutable prompt may remain as an audit
   artifact. Untrusted execution refuses before provider or storage work.
7. **No dependency rewriting or provider expansion is implied.** Patch impact
   reporting, server-owned provider configuration, schema vocabulary, and
   deterministic verification remain as established by ADR 0072.

## Consequences

- A single bounded candidate can produce a runnable target and its helpers,
  with real content refs for every admitted definition.
- Callers can address the generated target through the existing `/app/<name>`
  route after supervised read-model refresh.
- The request explicitly admits the supplied non-test bundle. This increment
  does not claim that every extra definition is reachable from the target;
  reachability constraints require separate design evidence.
- Existing single-term clients need no change. Internal typed-plan constructors
  gain one field and must state their target choice explicitly.

## Alternatives rejected

- **Any-type-match bundle admission:** ambiguous and order-dependent.
- **Source-order or naming conventions:** hidden protocol rules masquerading as
  inference.
- **A second bundle publication path:** duplicates the admission authority.
- **Per-helper RPC orchestration:** adds partial states and caller complexity
  without improving the admission invariant.
- **Mandatory dependency-closure analysis in this slice:** valuable future
  policy, but not required to make explicit bundle admission deterministic.

## Verification

Pending implementation. Required evidence:

- A red-then-green generation regression proving target plus helper admission,
  distinct content refs, verified target execution, and `/app` execution.
- Missing/wrong-typed target refusal without a new branch binding.
- Request/schema coverage for optional target and rejection of invalid input.
- Real MCP → loopback provider → admitted helper bundle → `/app` coverage.
- Legacy single-term generation coverage remains green.
- `gleam test`, `gleam format --check src test`,
  `gleam check --target erlang`, and `git diff --check` exit 0.

**Rich Hickey check:** one new optional value selects a subject in the existing
publication data. The rejected alternatives complect signature ownership with
source order, type coincidence, or a second write system.
