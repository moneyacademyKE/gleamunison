# Architectural Decision Record (ADR) 0036: Dogfood Benchmarking Methodology

## Context

The dogfood playbook (1000 levels) validates correctness by running each level through the full pipeline (parse → elaborate → type-check → compile → load → eval). However, correctness alone doesn't capture performance regressions. As the runtime grew (52 genesis modules, Mnesia storage, distributed concurrency, community libraries), we needed a way to measure and prevent performance degradation.

The benchmarking concern is orthogonal to correctness testing — it measures throughput and latency, not pass/fail — and thus should be decomposed into its own module per the de-complection principle.

## Decision

Create `dogfood_bench.gleam` as a dedicated benchmarking harness:

1. **Timing**: Uses `erlang:monotonic_time/0` (native Erlang function) for high-resolution wall-clock timing, avoiding system clock drift issues.
2. **Sample levels**: Benchmarks representative levels across the pipeline: Level 48 (arithmetic), Level 89 (builtins), Level 96 (JSON), Level 97 (HTTP), Level 98 (file I/O).
3. **Bootstrap isolation**: Each benchmark initializes a fresh codebase and loader, measuring end-to-end time from source text to evaluated result.
4. **Output**: Reports elapsed time in microseconds per level for regression detection.

## Status

Accepted.

## Consequences

- Performance regressions can be detected by re-running `gleam run -- bench` before releases.
- Benchmarking remains opt-in — it does not run as part of `gleam run -- all` (only correctness levels).
- Future extension points: memory usage tracking, repeated-trial statistical analysis, comparison against baseline runs.
- The module stays under 250 LOC by delegating evaluation to `dogfood_core.library_eval`.
