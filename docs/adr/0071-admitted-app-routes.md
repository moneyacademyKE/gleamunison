# ADR 0071: Admitted definitions served through application routes

- **Status:** Accepted
- **Date:** 2026-10-26 (EAT)
- **Tracking:** Bankai `bk-f728`
- **Implementation:** `d7a4441`
- **Related:** [ADR 0001](0001-content-addressed-identity.md), [ADR 0065](0065-verified-cas-admission.md), [ADR 0067](0067-production-boundaries.md), [ADR 0068](0068-durable-agent-read-model.md), [ADR 0069](0069-durable-db-ability.md), [ADR 0070](0070-admitted-agent-writes.md)

## Context

The factory could admit code and application facts, but a published definition
had no URL. The HTTP dispatcher was a fixed table of runtime and scratch
endpoints; only the CLI could execute admitted content directly.

The tempting shortcuts are all authority leaks: execute any hash in CAS,
promote session scratch into `/app`, accept a caller-selected branch, or add a
route-specific evidence check. Each would make the meaning of a route depend
on something other than the selected durable namespace and the existing
execution policy.

## Decision

1. **Two explicit POST route forms.**
   `POST /app/<name>` resolves a name in the server-selected branch.
   `POST /app/ref/<content-ref>` additionally requires that exact content to be
   bound somewhere in the same branch. `GLEAMUNISON_BRANCH` selects the branch
   (default `main`); the request cannot override it. Scratch and unbound CAS
   content return 404.
2. **JSON values, not source or Erlang terms.** The request body is exactly
   `{"args":[...]}`, with at most eight arguments and 65,536 bytes; an empty
   body means no arguments. Success is `{ref, branch, value}` and uses the same
   honest, depth-bounded term renderer as `run --json`. A rendered response
   over 1 MiB is refused rather than truncated into a misleading value.
3. **Execution policy remains in `run_ref`.** `app_route` resolves and decodes;
   `run_verified_raw_on_branch` owns existence, evidence, closure loading, and
   execution. `allow_unverified` is always false. There is no route-specific
   admission rule and no second evaluator.
4. **Transport policy is shared.** `/app/*` has the existing `data-write`
   scope. The Erlang adapter uses the same `admit_execution` profile gate as
   `/eval` and `/mcp`, before opening storage. `untrusted-execution` therefore
   returns 403 with `missing_external_executor`; this is not an OS-sandbox
   claim.
5. **Path segments are data.** `app_path` strictly decodes `%XX`, rejects bad
   escapes, NUL, invalid UTF-8, query strings, and raw or decoded separators.
   It does not change the legacy `/eval` decoder. A namespace `binds` query
   answers content membership directly without constructing a second name-ref
   map.
6. **Errors keep their meaning.** Invalid input is 400, oversized input is
   413, absent content is 404, evidence refusal is 403, and execution failure
   is 422. Storage/read/load failures remain explicit server errors. Clients
   can distinguish a missing route from a refused invocation.

## Consequences

- MCP publication and HTTP execution now share one selected branch+CAS view.
- Pure value/function routes and effectful Db-backed routes use the same
  contract. Application facts remain in `application.dets`, separate from CAS.
- `namespace_codec` owns canonical namespace/head bytes; `namespace` keeps
  namespace and branch semantics. The split preserves canonical content and
  keeps both modules below the file-size ceiling.
- This is not a web framework, router DSL, automatic REST/CRUD mapping, or a
  public unauthenticated application host. Those are not needed for the
  factory's in-database application loop.

## Alternatives rejected

- **Arbitrary `/run/<hash>` over any CAS content:** bypasses selected-branch
  admission and makes CAS presence a bearer capability.
- **Expose scratch through the same route:** makes unadmitted exploration
  indistinguishable from durable application code.
- **Caller-supplied `branch` or `store` fields:** lets the request replace the
  server's durable context and reintroduces a storage backdoor.
- **Route-local evidence or evaluation:** duplicates and eventually diverges
  from `run_ref`; rejected as complecting transport with execution policy.
- **A dependency or web framework:** rejected; the required surface is small,
  and the existing HTTP server already owns auth, body limits, and profiles.

## Verification (2026-10-26, EAT)

- Red receipts: unknown `app_route` module; then real-socket routes returned
  404 and untrusted execution returned 404 instead of the required 403.
  `720 passed, 2 failures` before HTTP dispatch was wired.
- `gleam test`: **724 passed, no failures**, including six new service/HTTP
  regressions and the explicit `/app` authorization-scope assertion.
- Real socket E2E: MCP `agent_publish` → `/app/<name>` and `/app/ref/<hash>` →
  the same content ref and JSON value; scratch remains 404.
- Durable application proof: HTTP Db write → forced Db-owner restart → HTTP Db
  read returns the committed EAV fact. Unsigned `io` evidence was refused;
  signed evidence passed through the ordinary turnstile.
- Hostile input tests cover malformed/unknown JSON fields, excess arguments,
  wrong arity, oversized bodies, encoded separators, malformed escapes, NUL,
  and branch override attempts.
- `gleam format --check src test`, `gleam check --target erlang`, and
  `git diff --check` pass. `namespace.gleam` is 420 LOC and
  `namespace_codec.gleam` 98; all new route modules are below 250 LOC.
