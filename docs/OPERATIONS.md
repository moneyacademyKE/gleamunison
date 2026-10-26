# Gleamunison operations runbook

## Supported boundary

The verified classification is **authenticated single-node service** for the
local factory/runtime loop. It is not an untrusted-code sandbox, a TLS server,
or a supported multi-node production cluster.

Use Erlang/OTP 27, 28, or 29 and a verified `gleamunison_escript`. See
[Build Escript](BUILD_ESCRIPT.md) for build/artifact checks and the latest
`docs/verification/production-boundaries-*.md` witness for measured results.

## Start locally

```sh
./gleamunison_escript --help
./gleamunison_escript server 8080
```

The port is the `server` argument; there is no `--port`, `--log-level`, or
`--loader-cache` server option. Loopback (`127.0.0.1`) and the `local` profile
are the defaults. With no HTTP tokens configured, protected routes are allowed
only behind the loopback bind contract; this is convenient local access, not
remote authentication.

Check the public probes:

```sh
curl -fsS http://127.0.0.1:8080/api/live
curl -fsS http://127.0.0.1:8080/api/ready
```

`/api/health` exposes the structured readiness report for compatibility.
Readiness returning 503 is a failed dependency/configuration check, not a
liveness contradiction.

## Configuration

The server and CLI read configuration from the environment. Important values:

| Variable | Default / purpose |
|---|---|
| `GLEAMUNISON_STORE_DIR` | `.gleamunison`; an explicit override must be absolute |
| `GLEAMUNISON_BRANCH` | `main`; server-selected durable branch |
| `GLEAMUNISON_BIND_ADDRESS` | `127.0.0.1` |
| `GLEAMUNISON_PROFILE` | `local`; also `authenticated-remote` or refusing `untrusted-execution` |
| `GLEAMUNISON_HTTP_TOKEN` | Admin bearer token; required by the non-loopback bind gate |
| `GLEAMUNISON_HTTP_WRITE_TOKEN` | Bearer scopes for public, data-read, and data-write routes |
| `GLEAMUNISON_HTTP_READ_TOKEN` | Bearer scopes for public and data-read routes |
| `GLEAMUNISON_SYNC_TOKEN` | TCP sync peer authentication |
| `GLEAMUNISON_REQUIRED_SERVICES` | Optional comma-separated required `http,mcp,sync` checks |
| `GLEAMUNISON_EVAL_TIMEOUT_MS` | Evaluation wall-clock budget |
| `GLEAMUNISON_MAX_MEMORY_MB` | Memory/readiness limit |
| `GLEAMUNISON_EVIDENCE_SIGNING_KEY` | Evidence signing/verification policy input |
| `GLEAMUNISON_STORE_ALLOW_UNVERIFIED` | Explicit local-only execution hatch; not a production default |

The LLM and evidence/key-rotation variables are documented in
[LLM policy](operations/llm-policy.md) and
[Trust and key rotation](operations/trust-and-key-rotation.md). Keep secrets in
the service manager's protected environment mechanism, not in source, branch
names, prompts, docs, or tickets.

## Remote exposure

A non-loopback bind requires both:

```sh
GLEAMUNISON_PROFILE=authenticated-remote
GLEAMUNISON_HTTP_TOKEN=<protected-admin-token>
```

Otherwise startup refuses. Configure `GLEAMUNISON_SYNC_TOKEN` separately when
sync is enabled; an HTTP credential does not authenticate a sync peer.

The runtime does not terminate TLS. A remote deployment needs an externally
managed TLS/authenticating proxy or equivalent trusted transport, plus network
policy appropriate to its exposure. The `authenticated-remote` profile still
executes in-process: it does not make hostile definitions safe.

Do not select `untrusted-execution` as a way to harden a normal remote server.
Its transport-facing admission currently refuses with
`missing_external_executor`; no approved external executor is configured.

## Application and agent surfaces

- `POST /mcp` uses the supervised durable/scratch session and server-selected
  store and branch.
- `agent_publish` and `agent_generate` pass the ordinary evidence/admission
  path; they are not direct storage writes.
- `POST /app/:name` and `POST /app/ref/:content-ref` execute selected-branch
  admitted definitions with bounded JSON arguments/results.
- Application `Db` facts live in `application.dets` beside the configured code
  store. Code content and application facts have separate lifecycles.

Request authorization is checked before these handlers, and execution-profile
admission is checked again at the execution/write boundary. See
[Deployment profiles](operations/deployment-profiles.md) and ADRs 0068–0072.

## Observability

- `GET /api/ready` — required-resource readiness; 503 on failure.
- `GET /api/live` — HTTP process liveness only.
- `GET /api/observability` — bounded metrics, saturation, recent logs/traces,
  and readiness.
- `GET /api/logs`, `/api/processes`, `/api/sync-status`, `/api/traces` —
  administrative inspection surfaces.

Admin routes require an admin-scoped bearer when tokens are configured:

```sh
curl -fsS -H "Authorization: Bearer $GLEAMUNISON_HTTP_TOKEN" \
  http://127.0.0.1:8080/api/observability
```

In-process logs, traces, and metrics are bounded caches, not durable history
or a monitoring/exporter service. Read
[Observability](operations/observability.md) for limits and saturation behavior.

## Backup and restore

The default store directory is `.gleamunison` under the service working
directory; an explicit `GLEAMUNISON_STORE_DIR` is absolute. Do not assume
`/tmp/gleamunison_*` or back up a live store with a wildcard copy.

1. Drain and stop writers/service so DETS and journal state are quiescent.
2. Preserve the entire configured store directory, including code, branch,
   evidence/log, and `application.dets` files that are present.
3. Record the artifact hash, `version`, `schema-version`, branch, and store
   path. Keep credentials separate and protected.
4. Restore into the same selected store path with the service stopped, then
   start and verify readiness plus an application read.

Test recovery on an isolated copy before relying on it. A successful process
restart alone is not a backup restoration proof.

## Upgrade and rollback

Drain and restart to replace the runtime artifact. Content-addressed loading
of user definitions is not a rolling upgrade mechanism for the runtime,
supervisors, evaluator, or CLI.

Follow [Upgrade and rollback](operations/upgrade-and-rollback.md) and run
`bb scripts/test_upgrade_rollback.clj` for the executable artifact/recovery
contract. Keep the previous verified binary and a quiesced store backup.
Schema equality is required unless a release supplies an explicit migration.

There is no documented supported rolling multi-node procedure here. Do not
join nodes, assume Mnesia replication is a production topology, or migrate
processes as though those boundaries were implemented.

## Troubleshooting

| Symptom | Check |
|---|---|
| Startup refuses a non-loopback bind | Profile, admin token, bind address; read the refusal rather than weakening it |
| 401 | Bearer presence and token class |
| 403 | Required scope or execution-profile refusal |
| 404 on `/app` | Selected branch, admitted binding, exact name/ref; scratch is not routable |
| 503 readiness | The named failed checks in the JSON report |
| Missing definition after restart | Actual absolute store path and selected branch; a different working directory can select a different default store |
| Stale agent view | Publication outcome and supervised session refresh; scratch may intentionally shadow a durable name |
| Missing application facts | `application.dets` recovery/journal and store path, not code CAS alone |

Run `bb scripts/verify_production_boundaries.clj` for the full local gate. Its
witness is evidence for that source/artifact/environment, not a substitute for
investigating the current live configuration.
