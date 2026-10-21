# Observability and Resource Boundaries

One policy, one owner: every runtime buffer is a bounded cache with a named
limit, and one module — `gleamunison_observability` — knows them all. Nothing
in-process is the system of record; the durable record is the evidence store.

## The bounds

| Surface | Limit | Saturation behaviour |
|---|---|---|
| HTTP workers | 64 | `503 busy`, socket closed |
| HTTP request body | 1 MiB | `413 request body too large` |
| HTTP headers | 64 headers / 16 KiB | `413 headers too large` |
| MCP in-flight requests | 64 | `{error, busy}` → `503` |
| SSE clients | 32 | `503 {"error":"sse client limit reached"}` |
| Sync TCP frame | 1 MiB | connection error, frame refused |
| Trace entries | 512 | oldest evicted (FIFO) |
| Log entries | 1024 | oldest evicted (FIFO) |
| Metrics series | 256 × 128 samples | new series dropped, existing keep recording |
| Metric name length | 128 bytes | refused at the API edge |
| Store listing | caller-supplied | `list_refs_bounded/2`, `dets_list_refs_bounded/2` |
| Readiness check budget | 150 ms per check | `check_timeout`, never hangs the report |

Mailbox depth is bounded structurally: HTTP workers and MCP requests are
spawned-per-request under the concurrency caps above, so no process accumulates
an unbounded queue behind a single owner.

## Redaction is a property of the write

Credential headers (`authorization`, `cookie`, `set-cookie`, `x-api-key`,
`proxy-authorization`, `x-sync-token`) are redacted to `[redacted]` **at
capture time** in `gleamunison_trace`. No reader — the traces route, the SSE
trace feed, or the observability export — can leak what was never stored.
The export additionally omits header values entirely; it carries counts,
names, and bounded recent summaries only. No env vars, no key material.

## Export

`GET /api/observability` (token-protected whenever `GLEAMUNISON_HTTP_TOKEN`
is set) returns machine-readable JSON:

```json
{
  "exported_at": "…",
  "metrics":   {"counters": {}, "gauges": {}, "histograms": {"name": {"count": 0, "min": 0, "max": 0}}},
  "traces":    {"count": 0, "limit": 512, "recent": [{"id": "…", "timestamp": "…", "method": "GET", "path": "/…"}]},
  "logs":      {"count": 0, "limit": 1024, "recent": [{"timestamp": "…", "level": "info", "message": "…"}]},
  "saturation": {"http_workers": 0, "http_worker_limit": 64, "mcp_active": 0, "mcp_request_limit": 64,
                 "sse_clients": 0, "sse_client_limit": 32, "trace_entries": 0, "trace_entry_limit": 512,
                 "log_entries": 0, "log_entry_limit": 1024},
  "readiness": { "…": "the full readiness report" }
}
```

`gleamunison_observability:saturation/0` is the single source for every
limit; readiness reads it so the limits and the probes cannot drift apart.

## Readiness

`/api/ready` reports storage, version, schema, memory, and configuration as
gating checks, plus four observational checks that inform but never flip the
verdict:

- **supervisors** — `gleamunison_sup` / `gleamunison_runtime_sup` /
  `gleamunison_metrics_sup` aliveness. Observational because if the tree
  dies, nobody answers this report at all.
- **queues** — compares live worker/client counts against the saturation
  table; `saturated:[…]` names the full queues.
- **codebase** — loaded module count from the code server.
- **provider** — `anthropic_configured` / `openai_configured` /
  `not_configured`. An unconfigured LLM provider is a valid deployment, so
  this is informational.

## Drain and crash/restart

`gleamunison_http:drain(TimeoutMs)` closes the listen socket and stops the
acceptor first — no new work arrives — then waits for in-flight workers to
finish, up to the timeout. Returns `drained` or `{timeout, Remaining}`. The
server process survives a drain; `stop_server/0` finishes shutdown. After a
drain the readiness http check reports `http_not_running` by design.

Crash/restart is proved, not assumed (`test/observability_recovery_test.gleam`):

- the metrics gen_server is killed and the supervisor restarts it with a new
  pid; the next `counter/2` lands without the caller noticing;
- the trace and log tables are deleted outright (the harshest crash — even
  the ETS owner is gone) and the next capture/log recreates them;
- a full HTTP drain leaves no listener registered and stops cleanly.

## Operator checklist

- Watch `saturation` fields approaching their limits; sustained saturation
  of `http_workers` or `mcp_active` means clients are seeing `503 busy`.
- Traces/logs are caches: anything that must survive a restart belongs in
  the evidence store, not here.
- Rotate nothing to keep these bounds honest — they are compile-time
  constants; changing them is a code change with a test.
