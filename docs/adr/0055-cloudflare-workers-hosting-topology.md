# ADR-0055: Cloudflare Workers Hosting Topology Decisions

## Context
A comparison was requested to understand the benefits and trade-offs of hosting `gleamunison` on Cloudflare Workers (serverless JS/WASM Edge) versus traditional VM-based Erlang BEAM hosting.

Traditional VM hosting supports native BEAM hot code reloading, process-isolated actors, ETS/DETS memory storage, and preemptive scheduling, but carries high operational overhead and clustering complexity. Cloudflare Workers offer instant global scale, zero server maintenance, and near-zero cold starts, but impose sandboxing constraints (no dynamic execution/compilation) and request-scoped database access.

## Decision
We evaluated the two options and decided to adopt a hybrid strategy:
1. **Self-Hosted BEAM as Primary for Compilers/REPLs**: Continue using the self-hosted Erlang/BEAM topology for deployments that require interactive code upgrades, REPL compilation, and distributed process migration.
2. **Cloudflare Workers for Read-Heavy Edge Sandboxing**: Support Cloudflare Workers as an optional deployment target for read-heavy API gateways, sandbox modest modding runtimes, and globally distributed static microservices, utilizing an AST interpreter.

## Consequences
- The project documentation and design logs have been updated to support both topologies.
- Storage code must remain pluggable to support both DETS (BEAM) and KV/Durable Objects (Cloudflare).
