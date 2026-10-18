# ADR 0066: Bounded readiness and supervised in-process metrics

- **Status:** Accepted
- **Date:** 2026-10-19 (EAT)
- **Tracking:** `bk-11fc`
- **Related:** [ADR 0010](0010-storage-adapter-pattern.md), [ADR 0021](0021-runtime-tradeoffs-and-robustness-safeguards.md), [ADR 0065](0065-verified-cas-admission.md)

## Context

The old readiness predicate was only `loaded_modules > 0`, so a node with no storage was reported ready. `/api/health` always returned HTTP 200 and exposed only a module count. HTTP, MCP, and sync listener state was not observed. Health checks could block indefinitely if a service stopped responding.

Metrics were stored in a public ETS table created by whichever process called the first metric function. A short-lived caller could own and destroy the table. Histogram calls created an unbounded ETS row per sample, and counters used a non-atomic lookup/update pair. These are small-node conveniences with production-shaped failure modes.

## Decision

1. Expose three probes: `/api/live` is liveness and returns 200 when the HTTP process answers; `/api/ready` is required-resource readiness; `/api/health` aliases the structured readiness report for compatibility. Readiness returns 200 only when all required checks pass and 503 otherwise.
2. Readiness reports safe structured data: `ready`, `status`, application `version`, definition `schema_version`, and bounded checks with `name`, `required`, `ok`, and `detail`. It checks active storage, manifest version, codec version, memory, configuration, and explicitly configured required listeners.
3. Keep listener requirements opt-in with `GLEAMUNISON_REQUIRED_SERVICES`, a bounded comma-separated subset of `http`, `mcp`, and `sync`. Unknown names or overlong configuration fail closed. A CLI/library node is not unready merely because optional listeners are stopped.
4. Use `GLEAMUNISON_MAX_MEMORY_MB` with default 4096 MB. Invalid, zero, or negative limits fail readiness. Each check runs in a monitored worker with a 150 ms deadline. A timeout is a failed check, not a hang or a false success.
5. Do not turn readiness into a full CAS audit, backup check, execution test, or provenance verifier. Partitioned DETS checks directory availability; Mnesia checks local table availability; schema version reports runtime codec support, not historical migration status.
6. Own metrics in a small supervised `gleamunison_metrics_sup`/`gleamunison_metrics` registry. Bound names to 1–128 bytes, retain at most 256 kind/name series, and retain at most 128 latest histogram samples per series. Drop invalid or over-cardinality new observations. Use ETS atomic counters, one gauge per name, and fixed telemetry event names with name metadata.
7. Registry restart is recovery, not persistence. It resets in-memory observations. The registry exists to survive caller lifetimes and keep cardinality/memory bounded without adding a monitoring dependency or daemon.

## Consequences

- Kubernetes/systemd-style probes can distinguish “process answers” from “required resources are usable.” False-green 200 readiness responses are removed.
- Deployments that require MCP/sync/HTTP must set `GLEAMUNISON_REQUIRED_SERVICES`; the default remains usable for a library/CLI node.
- A 150 ms per-check budget bounds health request work but can mark a loaded or heavily contended node unready. This is intentional: readiness is conservative and should be investigated, not silently stretched.
- Metrics no longer disappear when the first caller exits, and histograms cannot grow without limit. Over-cardinality observations are lossy by design and must not be treated as an audit log.
- No durable metrics, exporter, or automatic store repair is implied. `/api/status`, logs, and external telemetry remain separate operational surfaces.

## Alternatives considered

- **Count loaded modules:** rejected; it says almost nothing about storage, version, memory, or listener health.
- **Make every service mandatory:** rejected; it would make the CLI/library mode report unhealthy for intentionally absent listeners.
- **Scan every stored artifact on each probe:** rejected; it couples readiness latency to data volume and turns a health endpoint into a repair/audit job.
- **Use caller-owned ETS:** rejected; ownership is a hidden lifetime coupling.
- **Add Prometheus or a metrics database:** rejected; the requirement is bounded local observability, not a new service or dependency.
- **Block until slow checks finish:** rejected; a stuck health probe is itself an outage amplifier.

## Verification / follow-up

`test/production_readiness_test.gleam` exercises absent/open/closed storage, memory/config failures, HTTP 200/503 JSON contracts, liveness independence, all required listeners, and a suspended MCP timeout. `test/metrics_registry_test.gleam` exercises bounded histogram retention, caller lifetime, atomic counter accumulation, supervisor recovery, and name/cardinality limits. The explicit gate on 2026-10-19 EAT reported **405 passed, no failures** after the readiness implementation and **403 passed, no failures** after the metrics registry commit `8f372d9`.

The session's locked verifier still invokes bare `gleam` and reports exit 127; explicit PATH receipts are the actual checks. Compatibility/release proof must still verify standalone artifact metadata and truthful `--help`/unknown-command exits.
