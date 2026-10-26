# ADR 0070: Admitted agent writes through one MCP publication tool

- **Status:** Accepted
- **Date:** 2026-10-26 (EAT)
- **Tracking:** Bankai `bk-effa`
- **Related:** [ADR 0001](0001-content-addressed-identity.md), [ADR 0065](0065-verified-cas-admission.md), [ADR 0067](0067-production-boundaries.md), [ADR 0068](0068-durable-agent-read-model.md), [ADR 0069](0069-durable-db-ability.md)

## Context

Every MCP tool was read-only. An agent could inspect, search, and evaluate
code, but landing a definition still required the human CLI `test` →
`publish` pair. That gap was the first factory blocker: the generation loop
cannot close if its only write path is a shell a model must impersonate.

The obvious shortcut is a storage-shaped tool: `cas_write(hash, bytes)`,
`bind_branch(name, hash)`, or promoting `/define` scratch into the store.
Each makes MCP a second admission authority, re-opens the name-hash /
content-hash confusion fixed under `bk-56c2`, and lets a caller who can
spell a hash skip tests, evidence, and the turnstile entirely.

## Decision

1. **One write tool, source in, refs out.** `agent_publish` accepts exactly
   `{source: string}` (`additionalProperties: false`). No storage key,
   branch name, or store path crosses the MCP boundary. The branch is the
   server-selected one (`GLEAMUNISON_BRANCH`, resolved by
   `mcp_session.selected_branch()`); the store root comes from the
   lifecycle context, never from the request. The response is the
   publication receipt: admitted count plus each definition's real
   `content_ref`.
2. **The pipeline is reused, not re-spelled.** `agent_publish.publish_source`
   runs source → definitions-only load (`source_loader`, built on the now
   public `verify.require_forms`) → elaboration → tests with signed evidence
   → the same turnstile the CLI uses → CAS insert and selected-branch
   binding (`publication`). Untested pure definitions are refused.
   Effectful definitions need existing signed `io` evidence; the tool never
   invents a test to satisfy its own gate.
3. **Profile refusal happens before storage opens.**
   `mcp_write.check_writable()` denies `untrusted-execution` before
   `active_storage.active_or_open()` runs. The regression proves it: the
   DETS file is never created. Capability frames are not an OS sandbox and
   are not sold as one (ADR 0067 still owns that boundary).
4. **Publication serializes through the supervised owner.**
   `gleamunison_web_session:publish/1` calls `session_refresh.publish`:
   admit, then rebuild a fresh durable snapshot (`boot_configured`) and
   re-apply only the previous scratch overlay (`overlay_scratch`). Cache
   authority is explicit: fresh durable entries win for stored names;
   scratch name-refs are restored after the merge, so scratch shadows
   durable by name but a successful write never resurrects a stale stored
   type. Scratch survives publication; it is never silently absorbed into
   CAS and never silently dropped.
5. **The receipt must run.** The E2E contract is: MCP `agent_publish` →
   MCP `get_definition` returns the same `content_ref` →
   `run_ref.run_verified_on_branch` executes it on the selected branch →
   CLI `run <ref> --store … --branch …` returns the same value. A
   publication whose ref cannot execute is a failure of this ADR, not of
   the caller.

## Consequences

- Agents gain a write path whose admission rules are byte-for-byte the
  human ones. The turnstile stays the single owner of "may this be
  stored"; MCP adds a door, not a policy.
- The durable/scratch split from ADR 0068 survives writes: reads converge
  to the store after every publication, exploration stays session-local.
- `cli_run.run` and `verify.require_forms` became public so the agent path
  and the CLI path share one implementation instead of diverging copies.
- Rejected alternative: any hash-addressed or branch-addressed write tool.
  It would make the agent surface a second admission authority and turn
  content refs back into bearer write capabilities.

## Verification (2026-10-26, EAT)

- `gleam test`: 717 passed, no failures (was 714 at core-green; +3
  regressions: stale-type refresh, MCP E2E publish/run, untrusted refusal
  before storage).
- Red receipts: the refresh test fails against the previous-wins cache
  merge (`716 passed, 1 failures`) and passes against fresh-wins.
- `gleam format --check src test` clean; `gleam check --target erlang`
  clean; `git diff --check` clean.
- LOC: `mcp_session` 475 (was 505 mid-draft, split into `mcp_write` 50,
  `mcp_tools` 27, `session_refresh` 30); `agent_publish` 120,
  `publication` 131, `source_loader` 74.
