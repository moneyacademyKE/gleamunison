# Gap Analysis: gleamunison vs Darklang

A Rich Hickey-style Gap Analysis comparing the architectural paradigms of Darklang (Deployless, Trace-Driven Development, Migration-less DB) with the Gleamunison runtime on the BEAM.

---

## 1. Feature Set Differences

| Feature | Darklang | Gleamunison | Trade-off / Benefit |
|---|---|---|---|
| **Deploy Model** | Deployless (instant, live editor-to-infrastructure compile) | Dynamic Compile & Load (`code:load_binary`) | Both allow instant updates; Darklang couples the editor directly to production infrastructure. |
| **Development Loops** | Trace-Driven (debug using production input traces) | REPL & Unit Tests | Trace-driven makes visual bug fixing trivial; REPL/tests are standard and run offline. |
| **Database Semantics** | Migration-less DB (types are versioned in-place) | DETS / Mnesia (Content-addressed CAS) | Migration-less avoids lock-and-migrate schema downtime; DETS/Mnesia is simple and standard. |
| **Routing / Gateways** | Integrated HTTP/Event router built-in | HTTP server (`http.gleam` / FFI routes) | Integrated router handles instant deploys safely; FFI router has less abstraction. |

---

## 2. Capability Deep Dive & Recommendations

### Concept A: Trace-Driven Development (Request Interception)
* **Darklang Concept**: Capture real incoming HTTP/Event request payloads (traces) and store them in database tables. In the editor, developers can view these live values inside the variables.
* **Gleamunison Benefit**: We can introduce a `Trace` effect or HTTP middleware that logs request payloads (input body, headers, timestamps) into a DETS table. The Web Dashboard (built in Phase 6) can load these traces, allowing inline variable inspection in the dashboard definition editor.
* **Verdict**: **Adopt (High Priority)**. Tremendously increases the value of the dynamic web dashboard.

### Concept B: Migration-less Database Schema Evolution
* **Darklang Concept**: Instead of SQL migrations, schema changes are handled by creating new versions of strongly typed structures. Functions read and write old/new schemas, migrating records lazily.
* **Gleamunison Benefit**: Because types are content-addressed (their hashes represent their identity), changing a type produces a new hash. We can write conversion functions (modeled as pure adapters or algebraic effects) that load old hashes and lazily write them back under the new hash, avoiding global database lock-ups.
* **Verdict**: **Adopt (Medium Priority)**. A natural fit for our content-addressed codebase.

---

## 3. Complexity vs. Utility

| Element | Complexity | Utility | Recommendation |
|---|---|---|---|
| **A: Trace Logging** | Low | High | **Recommended**: Implement request tracing middleware in HTTP. |
| **B: Lazily-Migrated CAS** | Medium | High | **Recommended**: Implement type adapters for old content-addressed hashes. |
| **C: Integrated Infra Editor** | High | Medium | **Decline**: Keep editor disconnected; improve Web Dashboard editor. |

---

## 4. Actionable Path
1. **HTTP Request Tracing**: Add a tracer middleware to `http.gleam` that writes request inputs and outputs to a DETS database table when enabled.
2. **Dashboard Trace Viewer**: Update the Web Dashboard to fetch and display traces, allowing developers to replay mock requests in-editor.
3. **Type Adapters**: Build a schema conversion utility to dynamically translate records stored under old definition hashes.
