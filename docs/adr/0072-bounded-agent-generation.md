# ADR 0072: Bounded generation through admitted publication

- **Status:** Accepted
- **Date:** 2026-10-26 (EAT)
- **Tracking:** Bankai `bk-6e13`
- **Implementation:** `75083d8`
- **Related:** [ADR 0065](0065-verified-cas-admission.md), [ADR 0068](0068-durable-agent-read-model.md), [ADR 0070](0070-admitted-agent-writes.md), [ADR 0071](0071-admitted-app-routes.md), [ADR 0073](0073-target-selected-helper-generation.md)

## Context

`sap`, `schema_printer`, `prompt`, and `patch` were tested libraries with no
runtime composition. An agent could publish source after ADR 0070, but there
was no bounded path from a model completion to an admitted, runnable app.

The tempting compositions are all dishonest in a different way:

- trusting a candidate's self-declared signature without checking its inferred
  type;
- writing generated AST or bytes directly to CAS, bypassing tests and evidence;
- reconstructing source from stored ASTs so a patch can pretend to regenerate
  dependents, despite ADR 0068 making stored ASTs authoritative;
- accepting a branch, store path, provider credential, or arbitrary content key
  in the MCP request.

The runtime also distinguishes content refs from name refs. Ordinary stored
terms reference dependencies by name; rebinding a name can change a dependent's
next execution without changing the dependent's content hash.

## Decision

1. **A generation plan is typed data.** It contains a prompt template, raw
   variables, an `ast.Type` signature, and 1–8 attempts. The public MCP
   vocabulary is deliberately small: `int`, `float`, `string`, `bool`, `list`,
   and `(parameters) -> result`. Internal callers may construct richer core
   types.
2. **The prompt has checked content identity.** `prompt.put_checked` stores the
   complete template, including generation instructions, and reports CAS
   failures instead of returning a valid-looking ref after a failed write.
   `{{signature}}` is reserved and rendered with `schema_printer`.
3. **A candidate is an envelope, not authority.** SAP repairs a bounded
   near-miss completion. The decoder requires exactly `source` and `signature`,
   rejects empty/oversized source, and requires the signature text to match the
   rendered request. Source is capped at 256 KiB, completions at 1 MiB, and the
   initial rendered prompt at 64 KiB.
4. **The inferred type is checked before evidence or admission.**
   `agent_publish.publish_source_with_signature` requires one target term and
   compares its elaborated type, rendered by the same schema printer, with the
   requested shape. An echoed string cannot admit a differently typed value.
5. **There is still one publication path.** Every attempt goes through source
   loading, elaboration, tests, signed evidence, the trust turnstile, CAS, and
   the selected-branch binding owned by `agent_publish`/`publication`.
   Generation adds no storage or evidence privilege.
6. **Retries repair within a hard budget.** Provider errors and rejected
   candidates become feedback in the next prompt. Exhaustion returns the last
   rejection and leaves branch bindings unchanged. The immutable prompt may
   remain in CAS as an audit artifact; it is not a branch admission.
7. **The provider is server-owned and optional in verification.** Production
   uses the existing `llm.complete_env` effect and its budget/configuration.
   MCP input never supplies provider settings or credentials. Tests may inject
   a deterministic provider; the transport E2E uses a one-shot loopback
   OpenAI-compatible completion, not an external account.
8. **Generation serializes through the supervised session.** Successful
   admission refreshes the durable read model and preserves scratch exactly as
   `agent_publish` does. Only the generation RPC uses the extended timeout,
   derived from the hard attempt/provider ceilings, so a caller does not abandon
   live generation after the generic 30-second call timeout.
9. **Patch reports impact; it does not fabricate regeneration.** The outcome
   lists direct stored dependents of each published name by traversing actual
   AST name refs with `patch.dependents`. Existing dependents keep their content
   refs and follow the newly selected branch binding on their next verified
   execution. No AST-to-source conversion or automatic dependent rewrite is
   claimed.

## Consequences

- MCP `agent_generate` closes the loop from model text to a real content ref
  and an `/app` route, while `agent_publish` remains available for direct source.
- The first public contract admits one target term plus its tests per attempt.
  [ADR 0073](0073-target-selected-helper-generation.md) later added explicit
  target-selected helper bundles; requests without a target keep this
  single-term behavior.
- Signature schemas describe value shape, not effect discharge. Effectful code
  still requires the existing signed `io` evidence. Generated tests are evidence
  under the existing policy, not proof of functional correctness.
- Exhausted generation can leave immutable prompt bytes, but not new branch
  bindings. Publication's existing evidence/CAS failure behavior is unchanged.
- No external-provider call is required for repository acceptance, and none is
  claimed by the loopback E2E.

## Alternatives rejected

- **Direct CAS/AST publication:** bypasses the single admission owner.
- **Trusting the JSON signature field:** accepts interface claims contradicted
  by the actual elaborated term.
- **Automatic source reconstruction and dependent regeneration:** conflicts
  with ADR 0068 and confuses name rebinding with content rewriting.
- **Caller-selected storage, branch, provider, or keys:** turns generation into
  a storage/control capability instead of an admitted write.
- **A speculative general type-expression parser:** adds unrequested language
  surface; the small external vocabulary is explicit and testable.

## Verification

At implementation commit `75083d8`:

- `gleam test`: **734 passed, no failures**.
- Near-miss JSON publishes and runs through verified execution and `/app`.
- Retry feedback, exhaustion, invalid output, signature mismatch, reserved
  inputs, and untrusted refusal before storage are covered.
- Real MCP HTTP → loopback provider → SAP → signed admission → `/app` passes.
- A changed dependency reports its stored dependent; the unchanged dependent
  content ref executes against the new selected-branch binding.
- `gleam format --check src test`, `gleam check --target erlang`, and
  `git diff --check`: exit 0.

**Rich Hickey check:** generation is one composition of existing values and
policies, not a second write system. The rejected shortcuts complect model
confidence with identity, patch analysis with source fabrication, and provider
configuration with caller authority.
