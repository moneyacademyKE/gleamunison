# Deployment profiles and execution boundaries

A profile selects an execution/deployment contract; it is not a universal
“production” switch. Request authentication, transport encryption, effect
handlers, and OS isolation answer different questions.

The current verified classification is **authenticated single-node service**.
Read [Operations](../OPERATIONS.md) for setup and the latest dated production
witness for evidence. This guide describes the implemented gates and the
external obligations they do not replace.

## `local`

Intended for one operator, loopback development, local agents, and CLI use.

- HTTP binds to `127.0.0.1` by default.
- With no HTTP tokens configured, protected routes are allowed behind the
  loopback bind contract. This is not remote authentication.
- Evaluation uses the in-process scope, effect handlers, and resource budgets.
- The VM, host FFI, configured storage, and loaded definitions remain inside
  the operator's trusted computing base.

Useful checks:

```sh
curl -fsS http://127.0.0.1:8080/api/live
curl -fsS http://127.0.0.1:8080/api/ready
```

Liveness answers only whether HTTP can respond. Readiness returns 503 when a
required storage, version/schema, memory, configuration, or required-service
check fails.

A non-loopback bind under `local` refuses with
`non_loopback_requires_authenticated_remote_profile`.

## `authenticated-remote`

Intended for an explicitly operated single node exposed through an externally
secured transport.

### Implemented startup and request gates

A non-loopback HTTP bind requires:

- `GLEAMUNISON_PROFILE=authenticated-remote`
- a non-empty `GLEAMUNISON_HTTP_TOKEN`

Without both, startup refuses. The admin token is also the credential checked
by the current bind gate; read/write tokens alone do not satisfy it.

Configured bearer credentials resolve to scopes:

| Credential | Scopes |
|---|---|
| `GLEAMUNISON_HTTP_TOKEN` | `admin` |
| `GLEAMUNISON_HTTP_WRITE_TOKEN` | `public`, `data-read`, `data-write` |
| `GLEAMUNISON_HTTP_READ_TOKEN` | `public`, `data-read` |

`auth.required_scope` owns route classification. Public probes/static assets,
data-write application routes, and admin `/api/*` routes are distinct.
Evaluation, definition, MCP, and `/app` writes require data-write; admin
observability requires admin. A read-scoped token cannot authorize those
writes or admin routes.

TCP sync has its own `GLEAMUNISON_SYNC_TOKEN` and authenticated v2 handshake.
HTTP authentication does not authenticate a sync peer, and neither one secures
Erlang distribution/epmd automatically.

### External obligations the process cannot prove

The runtime does **not** terminate TLS or discover/validate a reverse proxy.
The startup gate checks profile and token presence, not certificate validity,
proxy identity, client certificate policy, or Internet exposure. The operator
must therefore provide and verify:

1. TLS or an equivalent protected transport before remote exposure.
2. Proxy/network authentication and forwarding rules appropriate to the
   deployment, without treating arbitrary forwarded headers as identity.
3. Firewall/network policy for every listener, sync port, and Erlang
   distribution endpoint.
4. Secret storage, rotation, logging, and certificate/proxy health checks.

`authenticated-remote` still uses in-process evaluation. It does not make
hostile code safe and is not a multi-tenant isolation claim.

## `untrusted-execution`

This profile is not an available sandbox mode. The transport-facing admission
policy constructs it without an approved external executor and refuses
execution/write admission with `missing_external_executor`.

MCP publication/generation checks this refusal before opening storage.
`/eval`, `/define`, `/mcp`, and `/app/*` pass the same execution-profile
admission. In-process budgets and effect frames cannot substitute for a
kernel/container boundary.

A future implementation would need an approved external executor with verified
identity, filesystem/network isolation, descendant cleanup, cancellation,
resource limits, and redaction evidence. Those capabilities are not claimed by
naming the profile or by having a data type for an executor.

## Identity and trust remain separate

| Object | What it proves |
|---|---|
| Content ref | Which canonical term/type is being executed |
| Branch pointer | Which names the selected branch currently binds |
| Evidence | What a signer attested about a subject under policy |
| Bearer identity/scope | Which routes a caller may use |
| Deployment profile | Which execution/startup boundary was selected |
| External executor | Where hostile code would actually be isolated, if implemented |

None substitutes for another. A valid hash is not authorization; a signature
is not semantic correctness; an authenticated request is not sandboxed code.

## Verification and release language

Use `test/transport_auth_test.gleam` for scope and bind decisions and
`bb scripts/verify_production_boundaries.clj` for the integrated local battery.
Record the selected profile, bind address, credential scopes (never secret
values), store path, artifact hash, and actual command results.

Do not upgrade “configured locally” to “safe remotely,” or “remote authenticated”
to “untrusted multi-tenant.” The current labels and exclusions are deliberate.
A contract, test, or witness does not authorize a deployment, tag, merge, or
release.
