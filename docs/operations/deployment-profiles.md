# Deployment profiles and production boundary contract

**Date:** 2026-10-20 (EAT)
**Status:** Contract frozen; enforcement is sequenced in the remaining production-gaps plan.
**Tracking:** Bankai `bk-c7bb`; GitHub issue [#25](https://github.com/moneyacademyKE/gleamunison/issues/25)

This document prevents a local research runtime from being mistaken for a remotely exposed or untrusted-code service. A profile is a startup contract, not a marketing label. If a required control is absent, the profile refuses instead of silently downgrading.

## Profiles

### `local`

**Purpose:** one operator, one node, loopback development, research, and local CLI use.

**Allowed boundary:** the local OS user and explicitly configured local storage/provider credentials. The VM, FFI, and loaded definitions are trusted by this profile; this profile makes no claim to isolate hostile code from the host.

**Required behavior:**

- Bind loopback by default.
- Keep remote sync and administrative routes disabled unless explicitly enabled.
- Use bounded request bodies, frames, workers, readiness checks, and in-process metrics.
- Treat evidence and CAS verification as integrity checks, not proof of authorship or safety.

**Refuse when:** a configuration requests a non-loopback bind without selecting `authenticated-remote`; a required local store/provider/recovery check fails; or an invalid resource limit is supplied.

**Proof:**

- `curl -fsS http://127.0.0.1:<port>/api/live` must return HTTP 200 and `{"live":true}`.
- `curl -fsS http://127.0.0.1:<port>/api/ready` must return HTTP 200 only when required checks pass.
- The final witness will record the exact startup configuration and `scripts/verify_production_boundaries.clj` result.

### `authenticated-remote`

**Purpose:** an explicitly operated remote single-node service.

**Allowed boundary:** authenticated clients and sync peers with declared scopes, encrypted transport, bounded frames, and replay/session binding. Authentication answers “who”; authorization answers “what”; encryption answers “can an observer read or alter the connection.” They are separate controls.

**Required behavior:**

- Require TLS/mTLS or a documented authenticated reverse-proxy contract before any non-loopback bind.
- Authenticate HTTP, MCP, admin, data, and sync routes consistently; no powerful route is exempt by accident.
- Bind request identity and scopes to the session/request and reject replay or missing identity.
- Keep the Erlang distribution cookie/epmd host-trust boundary explicit; TLS on an HTTP port does not secure distribution automatically.
- Keep local development available through the `local` profile rather than weakening this profile.

**Refuse when:** TLS/mTLS or the authenticated proxy contract is absent; route authorization is incomplete; sync peer identity cannot be authenticated; frames or sessions are unbounded; or the requested bind is non-loopback without this profile.

**Proof:**

- A focused transport-auth test must show unauthenticated rejection, insufficient-scope rejection, and authorized success.
- A live startup probe must show non-loopback refusal with missing transport/auth configuration.
- A loopback/authorized probe must show the same request succeeds with the declared scope.
- `test/transport_auth_test.gleam` and `test/tls_sync_test.gleam` are the planned focused gates; the integrated command is `bb scripts/verify_production_boundaries.clj`.

### `untrusted-execution`

**Purpose:** evaluate code supplied by a party that is not trusted with the node.

**Allowed boundary:** an approved OS/container executor owns the actual process, filesystem, network, CPU, memory, and descendant boundary. A BEAM scope, capability handler, or worker supervisor is an additional containment layer, not a complete sandbox.

**Required behavior:**

- Refuse execution unless the approved external executor is configured and its health/identity is verified.
- Assign every evaluation a scope with permitted descendants, deadline, cancellation, reduction/memory/concurrency budgets, and cleanup ownership.
- Deny direct FFI/jets and host authority by default.
- Redact secrets and sensitive inputs from errors, logs, traces, evidence, and transcripts.
- Make timeout/cancellation and executor failure machine-readable and non-successful.

**Refuse when:** the executor is missing, unapproved, unreachable, unauthenticated, or unable to enforce the requested limits; direct host FFI is requested; or cleanup cannot prove the evaluation scope is drained.

**Proof:**

- `test/execution_scope_test.gleam` must show child/grandchild cleanup after deadline and explicit cancellation.
- `test/sandbox_boundary_test.gleam` must show capability denial, resource refusal, and refusal when the executor is absent.
- The final witness must include the executor identity/configuration without including its secret and must label any manual OS/container check.

## Profile selection and downgrade rules

- `local` is the only default convenience profile.
- Selecting `authenticated-remote` or `untrusted-execution` is explicit and visible in startup/readiness output.
- Missing controls are failures. There is no automatic fallback from `authenticated-remote` to `local`, or from `untrusted-execution` to in-process evaluation.
- A process-scope timeout proves cleanup of the owned scope only. It does not prove kernel isolation.
- A signed evidence record proves that a signer attested to a subject under a policy. It does not prove that the subject is safe, correct, or authorized for every deployment.

## Operator checklist

Before calling a node production-capable, record:

1. Selected profile and bind address.
2. Request/sync identity and authorization scopes.
3. TLS/mTLS or reverse-proxy termination contract, if remote.
4. External executor identity and enforced limits, if untrusted execution is enabled.
5. Storage, schema, recovery, version, and readiness results.
6. Artifact hash and verification witness path.
7. Explicit exclusions and unresolved risks.

The profile contract does not authorize a tag, Hex publish, merge, deployment, or public release.

**Rich Hickey check:** three profiles with explicit refusal paths are simpler than one “production” switch that complects transport, authority, and sandboxing. Keep the boundaries separate so each can be tested and composed.
