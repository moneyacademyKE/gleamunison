# Rich Hickey Gap Analysis: Gleamunison (v3.12.0) vs. Unison (v1.5.0) + Unison Cloud

A version-locked Rich Hickey Gap Analysis of gleamunison v3.12.0 (hex.pm, 2026-10-10)
against the real Unison: UCM release/1.5.0 (2026-10-02) and Unison Cloud, open-sourced
under MIT on 2026-10-08 (Nimbus worker, API server, UI, client).

(src: github.com/unisonweb/unison releases + unison-lang.org/blog/unison-cloud-open-source + unison.cloud/docs, conf: h — 2026-10-11)

Supersedes the version coverage of `gap-analysis-v3.4.0-unison-gleam.md` (June 2026,
Unison v1.1.0/1.3.0). The architectural-divergence doc `gap-analysis-vs-unison.md`
remains separately valid and is not repeated here.

---

## 0. What moved since the last analysis

**Unison, June → October 2026:**

- **1.4.0 (2026-08-19)** — tooling release: `run>` watch expressions, codebase-lock
  controls, record accessors for higher-rank field types, merge fixes, MCP tweaks.
- **1.5.0 (2026-10-02)** — language release: **GADTs** (`type Foo a b where ...`),
  **GADT-indexed abilities** (index refinement for handlers), typed POSIX signal
  subscriptions in the runtime, variadic FFI specifications, better pattern-match
  diagnostics.
- **Unison Cloud open-sourced (2026-10-08, MIT)** — Nimbus (cluster worker, written in
  Unison), the Haskell API/control-plane server, and the web UI joined the already-open
  client. The whole platform is now self-hostable.

**Gleamunison, v3.4.0 → v3.12.0:**

- The full LLM surface landed: `LLM` ability with OpenAI/Anthropic providers,
  retry/fallback/record middleware as plain handler composition, the SAP tolerant
  parser, content-addressed prompt storage, compact schema printer, and a CLI entry
  (`gleam run -- llm`). Root-caused JSON decode fix included. 116/116 tests green.

So the comparison shifted on both sides: Unison grew a type system and open-sourced a
cloud; we grew the agent-facing surface Unison still lacks.

---

## 1. Feature Set Comparison

| Capability Area | Unison v1.5.0 + Cloud | Gleamunison v3.12.0 | Trade-off / Benefit |
| :--- | :--- | :--- | :--- |
| **Type system** | HM + **GADTs** (1.5.0) | HM + ADTs | Unison pulled ahead. GADTs are research-grade expressiveness; our niche (agent tooling) rarely needs them, but the gap is now real, not theoretical. |
| **Abilities** | Algebraic effects, **GADT-indexed** (index refinement in handlers) | Handler stacks on BEAM processes | Their indexing is genuinely elegant for protocol-state machines. Ours compose with plain functions — their middleware story needs the language; ours needs `fn(h) { ... }`. |
| **Types in the hash** | Yes — 512-bit SHA3 of term+type structure | No — types computed, stored separately (ADR-0002) | Documented deliberate divergence. **Cost rose with GADTs**: type identity is now load-bearing for term identity in Unison; our divergence forecloses that whole design lane. |
| **Distribution** | **Unison Cloud**: `Remote` ability ("the I/O of the cloud"), `deploy`/`submit`, ServiceHash-addressed services, Nimbus workers | Native BEAM distribution + TCP pull sync | They built a platform; we inherited OTP's 40 years. Theirs ships exactly-once stream processing as a library *today* (Volturno); ours ships the substrate and the philosophy, not that library. |
| **Cloud storage** | `Storage`/`Transaction` abilities, Cell/OrderedTable/Database over DynamoDB, object storage over S3 | DETS + Merkle DAG storage adapter | Theirs is managed and transactional across a cluster; ours is local, embedded, zero-dependency. Different problem, honestly. |
| **Deploy story** | ServiceHash content-addressed deploys, stable ServiceName URLs, daemons (auto-restarted threads on every node), secrets via `Environment.Config` | escript single binary + hot swap + supervision | Both content-address deploys (ServiceHash ≈ our definition hash). They have a hosted control plane; we have one file you can scp. |
| **Agent surface (MCP)** | **UCM is an MCP server** (1.1+): `history`, `reflog`, `share-project-info` tools for AI agents | Datalog engine with BM25 + vector search over the codebase — but **no agent-facing protocol** | **Cheapest gap to close and they proved the demand.** We have the better query engine; they have the socket. MCP server over our HTTP stack is a small module. |
| **LLM programming surface** | None. MCP lets agents *read* the codebase; nothing lets programs *call models* | `LLM` ability, provider handlers, retry/fallback/mock middleware, SAP repair, content-addressed prompts | **We lead, decisively and new since June.** Different axis than MCP — theirs is code-query, ours is model-calls-as-effects. They have zero here. |
| **Structured-output repair** | None | SAP (fences, yapping, trailing commas, unquoted keys, comments, Python literals) | We lead. Nothing comparable exists in the Unison ecosystem. |
| **Prompt versioning** | N/A | Prompts as hashed DAG definitions | Structural lead — falls out of content addressing for free. |
| **Watch mode** | `run>` watch expressions (1.4.0) | None | Small, real DX gap. REPL FFI exists; a file-watcher re-evaluating marked expressions is a bounded piece of work. |
| **Crypto builtins** | Argon2id password hashing (1.1) | HMAC only | Table stakes for the web surface we already ship. Pure-Erlang or NIF jet; bounded. |
| **Update propagation** | Named **patches** (`diff.update`/`patch`) rewrite dependents of a changed hash | Migrations + instant hot swap | Theirs is a first-class codebase entity with a workflow; ours is machinery without the named-entity veneer. Formalizing "old hash → new hash, rewrite dependents" as a DAG node closes it. |
| **Editor** | VS Code integration, Share deep-links | LSP doc, REPL, dashboard, trace inspector | Theirs is polished for individuals; ours is self-hosted and agent-oriented. |
| **Test story** | `test>` watch expressions, io tests | dogfood framework, property testing, coverage runner, 116-test suite | Roughly at parity, different shapes. |
| **Code hosting** | Unison Share (with comment sync, 1.1) | Peer-to-peer TCP sync, no central hub | They have the social network; we have no hub dependency. Not a gap to close — a different bet. |

---

## 2. The three that matter

### 2.1. GADTs and GADT-indexed abilities — the one real language gap

Everything else in 1.4/1.5 is tooling. This is the type system pulling away: GADTs let
a type's *index* carry information (length-indexed vectors, typed protocol states), and
GADT-indexed abilities let a handler's effect row be refined by the index — e.g. a
`Protocol s` ability whose available operations depend on the session state `s`, checked
statically.

**Honest verdict:** we cannot express this on HM + ADTs, and bolting GADTs onto the
current inferencer is research-grade work. It is also the *only* Unison 1.5 feature our
niche might eventually feel. Watch whether Unison's ecosystem actually builds
load-bearing libraries on GADT-indexed abilities over the next two releases; if Volturno-
grade libraries start requiring them, revisit. Until then: **deferred, with a tripwire.**

### 2.2. Unison Cloud open-sourced — the platform gap became self-hostable

Three days ago the Cloud story changed from "their SaaS" to "MIT code you can run":
Nimbus workers (written in Unison itself), the Haskell control plane, the UI. The
programming model is genuinely Hickey-clean: `Remote` is "the I/O of the cloud," services
are typed content-addressed functions, storage is an ability, and Volturno demonstrates
exactly-once distributed stream processing *as a library* on those primitives.

**What we have instead:** distributed Erlang, supervision, hot swap, TCP pull sync. Raw
substrate with decades of production scars — but no `deploy`, no ServiceHash registry, no
transactional cluster storage, no daemons.

**Verdict:** this is a product gap, not a substrate gap, and closing it means deciding to
become a platform — a scope decision, not a feature. The composable middle path if it is
ever wanted: model remoting as a **`Remote` ability whose handler is distributed Erlang** —
handlers already make location a runtime decision, which is the entire trick Unison Cloud
plays. Do not build Nimbus. **Deferred by design.**

### 2.3. MCP — they proved agents want a protocol socket into the codebase

Unison 1.1 made UCM an MCP server so agents can query types, hashes, dependents, and
docs over JSON-RPC. We have the *stronger* query substrate — a datalog engine with BM25
and vector search over a content-addressed store — and **no socket in front of it**.

**Verdict:** this is the cheapest lead-extension available. An MCP server module over the
existing HTTP stack, exposing datalog queries as tools, is a bounded piece of work that
converts an internal strength into the exact surface agents already speak. **Do this one.**

---

## 3. Recommended moves, priority order

1. **MCP server over the datalog codebase engine** — small module, existing HTTP stack,
   converts our best internal capability into the protocol agents already speak.
   *(Lead extension, cheap.)*
2. **`run>`-style watch mode** — file watcher re-evaluating marked expressions via the
   existing REPL FFI. Pure DX. *(Parity, cheap.)*
3. **Argon2id jet** — password hashing for the web surface we already ship. *(Parity, bounded.)*
4. **Named update-propagation entity in the DAG** — formalize "old hash → new hash,
   rewrite dependents" on top of existing migrations + hot swap. *(Parity, medium.)*
5. **GADTs — deferred with a tripwire.** Revisit when Unison libraries make GADT-indexed
   abilities load-bearing, or at their v1.6/1.7, whichever first.
6. **Remote/cloud abilities — deferred by design.** If distribution beyond OTP is ever
   wanted, it is a `Remote` ability over distributed Erlang, never a control plane.

## 4. Declined

- **Chasing GADTs now** — research-grade cost, no current niche demand.
- **Building a hosted cloud / control plane** — explicit non-goal. The escript is the
  platform story; OTP is the cluster story.
- **A Share-like central code hub** — peer sync by hash is the bet; hubs can come later
  as dumb caches without changing the model.

---

## 5. Rich Hickey certification

Unison answered "how do programs distribute?" by building a cloud, and "how do agents
integrate?" with a read-only query protocol. We answered distribution by inheriting OTP,
and agent integration by making *model calls* a composable effect. Both decomplected
different things. The gap list above is honest: one real language gap (GADTs, deferred
with a tripwire), one product gap (Cloud, deferred by design), and one socket gap
(MCP) that costs us a week and converts a strength into a surface. Simplicity check:
nothing recommended adds a dependency, a control plane, or a new concept — each is an
existing substrate with a name or a socket put in front of it.
