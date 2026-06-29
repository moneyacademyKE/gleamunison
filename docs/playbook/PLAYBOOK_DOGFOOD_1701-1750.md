# Dogfooding Playbook — Levels 1701–1750

Batch 16: HTTP server integration, health variants, effects stacking, datetime pipelines, template, config, sync error recovery, storage stress, compile stress, loader error cache, jets, inference edges, and 14 cross-module integration chains.

---

## HTTP Server Integration (1701–1707)

**1701** — Start server, GET /eval?expr=42 via HTTP client, stop server
**1702** — Start server, POST /define?name=myval&expr=99, GET /browse, stop
**1703** — /api/status + /api/health via HTTP client
**1704** — /api/modules + /api/logs
**1705** — /api/processes + /api/sync-status
**1706** — /api/traces + /api/redefinitions
**1707** — /api/traces/nonexistent-id (404/error path)

## Health Variants (1708–1710)

**1708** — All-pass → Healthy("...")
**1709** — All-fail → Unhealthy("Failed checks: ...")
**1710** — Mixed pass/fail → Unhealthy (Degraded documented but not produced)

## Effects (1711–1713)

**1711** — RuntimeConfig with empty handlers
**1712** — ability_key derived from hash_to_debug_string (deterministic)
**1713** — Different refs produce different keys

## Datetime Pipeline (1714–1717)

**1714** — now() → to_iso8601 → from_iso8601 → to_iso8601 roundtrip
**1715** — add_seconds(3600) + diff_seconds
**1716** — diff_seconds zero (same moment)
**1717** — add_seconds(-60) negative diff

## Template + Filepath (1718–1719)

**1718** — render with 5 variable placeholders
**1719** — Full filepath chain: join, parent, file_name, extension, has_extension, with_extension

## Config CLI Precedence (1720–1722)

**1720** — StringVal CLI override
**1721** — IntVal + BoolVal CLI overrides
**1722** — cli > env precedence (USER override)

## Sync + Storage (1723–1726)

**1723** — pull_sync with nonexistent peer → error
**1724** — PeerStatus variants (Connected, Disconnected, Syncing, Failed)
**1725** — DETS 500-insert batch
**1726** — inmemory 5000-insert stress

## Compile + Loader (1727–1728)

**1727** — 100 simple defs compiled sequentially
**1728** — Loader compile-failed error cache + retry detection

## Jets + Inference (1729–1732)

**1729** — get_jet on nonexistent ref → None
**1730** — get_jet on known ref → Some(...) or None
**1731** — check_linearity on Let
**1732** — check_linearity on Apply

## AST Edges (1733–1734)

**1733** — Use term construction
**1734** — Handle(Hole, Int(0), ref) construction

## Cross-Module Integration (1735–1748)

**1735** — HTTP + REPL + Metrics
**1736** — HTTP + Log + Health
**1737** — Storage + Codebase + Loader + Compile
**1738** — Datetime + Filepath + JSON
**1739** — Config + Template + Log
**1740** — Crypto + Identity + DateTime
**1741** — Effects + TypeCache + Health
**1742** — Sync + HTTP + Metrics + Log
**1743** — REPL + Pipeline + Compile
**1744** — Inference + Codebase
**1745** — Loader + Storage
**1746** — Property + Metrics + Log
**1747** — Jets + Compile + REPL
**1748** — Filepath + Template + Config

## Certification (1749–1750)

**1749** — Batch 16 summary
**1750** — v2.8.0 certification banner: 772 dogfood + 53 unit = 825 verifications
