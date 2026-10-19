# Gleamunison Operations Runbook

## Deploy

### Prerequisites
- Erlang/OTP 26+ installed on target machine
- The `gleamunison_escript` binary (~1.2 MB)

### Deploy Steps
```sh
# 1. Copy escript to target
scp gleamunison_escript user@host:/opt/gleamunison/bin/gleamunison_escript

# 2. Make executable
chmod +x /opt/gleamunison/bin/gleamunison_escript

# 3. Start server (binds to 127.0.0.1 by default)
/opt/gleamunison/bin/gleamunison_escript server 8080
```

### Systemd Service (optional)
```ini
[Unit]
Description=Gleamunison Runtime
After=network.target

[Service]
Type=simple
ExecStart=/opt/gleamunison/bin/gleamunison_escript server 8080
Restart=always
RestartSec=10
Environment=GLEAM_LOG_LEVEL=info

[Install]
WantedBy=multi-user.target
```

## Configure

### Environment Variables
| Variable | Type | Default | Description |
|---|---|---|---|
| `GLEAM_LOG_LEVEL` | String | `info` | Log level: debug/info/warn/error |
| `GLEAM_SERVER_PORT` | Int | `8080` | HTTP server port |
| `GLEAM_SYNC_PEERS` | String | `-` | Comma-separated peer node names |
| `GLEAM_STORAGE_PATH` | String | `/tmp` | DETS/Mnesia storage path |

### Runtime Config
Use the CLI to override config at startup:
```sh
./gleamunison_escript server 9090
./gleamunison_escript --port 9090 --log-level debug
```

## Monitor

### Health and readiness

The runtime exposes three deliberately different probes:

- `GET /api/live` is liveness only and returns `200` while the HTTP process can answer.
- `GET /api/ready` is required-resource readiness. It returns `200` only when storage, application version, definition-codec schema, memory, and configured required services pass; failure is structured JSON with HTTP `503`.
- `GET /api/health` is the same structured readiness report for compatibility. It no longer returns a false-green `200`.

The JSON report contains `ready`, `status`, `version`, `schema_version`, and bounded `checks` entries with `name`, `required`, `ok`, and a safe detail. Set `GLEAMUNISON_REQUIRED_SERVICES` to a comma-separated subset of `http,mcp,sync` when those listeners are required for this deployment. Invalid service names fail closed. `GLEAMUNISON_MAX_MEMORY_MB` defaults to `4096`; invalid or non-positive values fail readiness.

Readiness is not a backup check, a full CAS audit, a code-execution test, or provenance proof. Each sequential worker has a 150 ms timeout (seven timed probes, plus configuration parsing). Closed stores and unresponsive services fail their checks. Partitioned DETS currently checks directory availability, not every shard; Mnesia checks that the local table is available. `schema_version` describes runtime codec support, not an audited on-disk migration level.

### Bounded in-process metrics

`metrics.counter`, `metrics.gauge`, and `metrics.histogram` use a dedicated supervised registry rather than ETS owned by the first caller. The registry admits at most **256 kind/name series**, names of **1–128 bytes**, and the most recent **128 histogram samples per series**. New series beyond the cap and invalid names are dropped; existing admitted series continue updating. Counters use ETS atomic increments. `gleamunison_metrics:list_metrics/0` is the bounded in-process inspection surface.

Telemetry events, when the optional telemetry module is present, use fixed `[gleamunison, counter|gauge|histogram]` event names with numeric `value` measurements and `name` metadata. No Prometheus/StatsD exporter, durable metric history, or external monitoring service is shipped. Registry restart recovers the worker but resets its in-memory observations; survival of short-lived callers is not durability.

## Upgrade

### Hot Upgrade (content-addressed)
1. Push new definitions to the codebase via REPL or HTTP API
2. Content-addressed hashing ensures no recompilation of unchanged code
3. `code:load_binary/3` loads new modules; old modules soft-purged when unused

### Rolling Upgrade (multi-node)
1. Start new nodes with updated escript
2. Join cluster: `net_adm:ping('newnode@host')`
3. Mnesia replicates definitions automatically
4. Drain old nodes: terminate after all processes migrated

### Rollback
- Content-addressed: previous definitions remain in storage; just load old hash
- Escript: replace binary and restart

## Troubleshoot

### REPL hangs
```sh
# Kill and restart REPL
./gleamunison_escript repl
```

### Server not responding
```sh
# Check process
curl http://localhost:8080/api/health

# View logs
curl http://localhost:8080/api/logs

# Check processes
curl http://localhost:8080/api/processes
```

### Module load failures
```sh
# List loaded modules
./gleamunison_escript repl
> (list-loaded-modules)

# Purge and reload
> (purge-module "m_abc12345")
> (define my-fn (lam x x))
```

### Memory pressure
- Restart server to clear accumulated definitions
- Reduce LRU cache size via `--loader-cache 100`
- Clear ETS tables: `ets:delete_all_objects(gleamunison_logs)`

### Sync failures
```sh
# Check cluster connectivity
net_adm:ping('peer@host')

# View sync status
curl http://localhost:8080/api/sync-status
```

## Backup & Restore

### Backup
DETS files are stored in `/tmp/gleamunison_*` by default.
```sh
cp /tmp/gleamunison_* /backup/
```

### Restore
```sh
cp /backup/gleamunison_* /tmp/
# Restart server; DETS auto-repairs
```

## Security

- The HTTP server binds to `localhost` by default; use a reverse proxy for internet exposure
- Content-addressed definitions are cryptographically immutable
- No authentication built into v1.0; use firewall + reverse proxy for access control
