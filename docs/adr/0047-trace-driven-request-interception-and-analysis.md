# ADR 0047: Trace-Driven Request Interception and Analysis

## Context
1. **Debuggability of Live Backend APIs**: Traditional backend debugging requires replicating database records or analyzing logs.
2. **Darklang's Trace-Driven Advantage**: Darklang captures real HTTP request payloads and visualizes them inline in the editor, allowing logic to be tested directly on production inputs.
3. **Dynamic BEAM HTTP Server**: Our `gleamunison` runtime runs Cowboy/Inets web server routing (`http.gleam`). We can intercept request handlers and log execution parameters safely without stopping the server.

## Decision
1. **HTTP Tracer Middleware**: Implement a trace-interceptor middleware in `http.gleam` that automatically writes incoming request parameters (headers, body, query strings) to a dedicated DETS/Mnesia table under a request ID.
2. **Visual Trace Overlays**: Expose the trace logs via the Web Dashboard, letting developers select historic request payloads and view variable values mapped directly to the live request trace in the dashboard editor.

## Consequences
* Simplifies developer onboarding and API testing by providing instant mock contexts.
* Zero-deployment visual verification: developers can check logic against actual request logs before upgrading modules.
