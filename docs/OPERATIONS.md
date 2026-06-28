# Gleamunison Operations Runbook

## Deploy

### Prerequisites
- Erlang/OTP 26+ installed on target machine
- The `gleamunison` escript binary (~1.2 MB)

### Deploy Steps
```sh
# 1. Copy escript to target
scp gleamunison user@host:/opt/gleamunison/bin/gleamunison

# 2. Make executable
chmod +x /opt/gleamunison/bin/gleamunison

# 3. Start server
/opt/gleamunison/bin/gleamunison server 8080
```

### Systemd Service (optional)
```ini
[Unit]
Description=Gleamunison Runtime
After=network.target

[Service]
Type=simple
ExecStart=/opt/gleamunison/bin/gleamunison server 8080
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
./gleamunison server 9090
./gleamunison --port 9090 --log-level debug
```

## Monitor

### Health Checks
```
GET /api/health → {"status":"healthy","loaded_modules":52}
GET /api/status  → node info, memory, uptime
```

### Key Metrics
- **Memory**: `< 4GB` is normal for development workloads
- **Loaded modules**: Should match genesis count (52) + user definitions
- **Process count**: Normal range 50–200 per node
- **Message queue length**: Per-process queues should stay `< 100`

### Prometheus/StatsD (planned)
Gleamunison emits typed telemetry events via `:telemetry`. Attach reporters:
```erlang
:telemetry.attach("prometheus-reporter", [:gleamunison, :compile], handler, nil)
```

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
# Kill and restart REPl
./gleamunison repl
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
./gleamunison repl
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
