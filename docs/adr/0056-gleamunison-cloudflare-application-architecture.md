# ADR-0056: Gleamunison Cloudflare Application Architecture Decisions

## Context
An architectural decision was needed on what a `gleamunison` application hosted on Cloudflare Workers would look like, how it would execute, and how generating and debugging it compares to traditional frameworks like SolidJS.

In SolidJS, applications are written in JSX/TypeScript, compiled statically by Vite, and deployed as complete javascript bundles. Debugging is done via standard stack traces, breakpoints, and reactivity graphs.

## Decision
We defined the architectural model for a Cloudflare-hosted `gleamunison` app:
1. **Dynamic AST Interpreter Host**: The Worker is deployed as a static, pre-compiled JavaScript bundle (compiled from Gleam) running a parser, typechecker, and recursive AST interpreter.
2. **Zero-Deploy Code Syncing**: Application code is structured by content address (SHA256 of AST). Deploying new logic does not redeploy the Worker; instead, it performs a Merkle diff exchange to push new AST definition hashes to Cloudflare KV.
3. **Trace-Driven Debugging**: All external operations are modeled as algebraic effects. The runtime records a complete execution trace (inputs, effect calls, handler responses). Debugging is achieved via deterministic local replay of these traces against mock handlers.

## Consequences
- The development lifecycle separates the static runtime (Worker engine) from the dynamic business logic (stored as content-addressed data).
- Debugging shifts from step-by-step breakpoint analysis to trace replay, making it extremely easy to debug edge failures.
