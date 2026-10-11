# Gap Analysis: gleamunison vs BAML

A Rich Hickey-style Gap Analysis comparing BAML (Boundary's LLM-function DSL, now pivoting to a full agent-first language in v1 beta) with the gleamunison runtime on the BEAM (v3.11.0).

(src: docs.boundaryml.com + new.boundaryml.com + gleamunison.hexdocs.pm, conf: h — 2026-10-10)

---

## 0. Framing — what BAML actually is in 2026

BAML is no longer just "a prompting DSL":

- **BAML v0 (legacy)**: declarative DSL for LLM functions — typed inputs/outputs, Jinja prompts, client registry with retries/fallbacks, Schema-Aligned Parsing (SAP), semantic streaming, multimodal types (image/audio/video/pdf), VSCode playground, test blocks, codegen of typed clients for Python/TS/Ruby/Go/Java, Boundary Studio observability.
- **BAML v1 (public beta, pre-1.0)**: a Turing-complete, TypeScript-flavored programming language "for software written by agents and humans" — runtime types with no `any`, typed errors, exhaustive matching, green threads (`spawn`/`await`), native LLM functions, testsets/evals, `baml describe` (AST-aware code discovery for agents), `baml run`, SDK generation for incremental adoption.

So the honest comparison is twofold: **(a)** BAML-the-LLM-toolkit vs gleamunison's missing AI surface, and **(b)** BAML-v1-the-language vs gleamunison-the-language. On (b) gleamunison is the stronger *runtime* (content addressing, hot swap, real effects, BEAM preemption and distribution). On (a) gleamunison currently has **zero LLM surface** — no prompts, no provider clients, no structured-output machinery. That is the gap.

---

## 1. Feature Set Differences

| Feature | BAML (v0/v1) | Gleamunison | Trade-off / Benefit |
|---|---|---|---|
| **LLM function definition** | First-class `function F(x) -> T { client; prompt }` | None | BAML: one artifact = prompt + schema + client. Gleamunison: would compose existing pieces (template + http_client + json). |
| **Structured-output parsing** | SAP — edit-distance repair of malformed JSON, trailing commas, fractions, yapping; beats native structured outputs on benchmarks | `gleamunison/json` strict decode only | SAP is BAML's crown jewel; strict decode fails on real-world model output. |
| **Schema emission** | `ctx.output_format` macro; ~80% fewer tokens than JSON Schema | Types-as-computed-metadata + `type_pretty` exist, no prompt emission | Gleamunison already knows the type; emitting BAML-style compact schema is a printer, not a feature. |
| **Provider abstraction** | Client registry: retries, exponential backoff, fallback chains, round-robin | `gleamunison/http_client` only | BAML config-couples it; gleamunison's **effect handlers would subsume it** (retry/fallback/mock as composable handlers, no codegen). |
| **Mocking / determinism** | Recorded fixtures via Boundary Studio | Algebraic effects with handler stacks | **Gleamunison leads**: an `LLM` ability makes the live call and the test mock the *same* handler swap. BAML needs a studio; we need a pure handler. |
| **Prompt versioning** | Git files, manual | Content-addressed Merkle DAG, pull sync, hot swap | **Gleamunison leads decisively**: prompts as hashed definitions — immutable, diff-able, deployable with zero downtime, distributable to peers by hash. |
| **Evals / testsets** | Native `test` blocks, testsets, eval harness | Playbook conformance harness (5696 levels) + unit suites | Equivalent infrastructure exists; needs an LLM-test mode with recorded traces. |
| **Streaming structured output** | Semantic streaming, partial types (`@stream.done`, `@stream.with_state`) | Processes/`recv` exist; no incremental parser | Medium-high complexity to match; BEAM processes are a natural sink for token streams. |
| **Multimodal inputs** | `image`, `audio`, `video`, `pdf` types with URL→base64 transcoding | No media types | Add as opaque types + FFI jets. |
| **Code discovery for agents** | `baml describe` — AST-aware query surface | **Datalog engine with BM25 + vector search over a content-addressed codebase** | Gleamunison can beat this nearly free: the codebase is already a queryable DAG; semantic code search is a datalog query away. |
| **Tool/function calling** | Classes as tool schemas, generated client stubs | Definitions already have hashes and types | Hash = tool identity. An agent can *pull a tool by hash from a peer* — BAML has no distribution story at all. |
| **Host-language SDKs** | Codegen to Python/TS/Ruby/Go/Java | escript single binary + Erlang distribution | Different philosophy; decline codegen, ship the runtime. |
| **Editor DX** | VSCode playground: run prompts inline, token counts, instant feedback | LSP doc, REPL, web dashboard, trace inspector | Playground ≈ dashboard + REPL wired to an LLM ability; medium gap. |
| **Observability** | Boundary Studio (hosted tracing) | Trace inspector (DETS capture, SSE, `/api/traces`) | Extend existing tracer to LLM calls; self-hosted by default. |

---

## 2. Capability Deep Dive & Recommendations

### Concept A: LLM calls as an algebraic ability (`LLM`)
* **BAML concept**: `client<llm>` blocks with provider, options, retry policy, fallback chains.
* **Gleamunison benefit**: Define `ability LLM { complete : Messages -> Completion }`. Providers are *handlers*; retry is a *handler*; fallback is a *handler*; the test mock is a *handler*. What BAML complects into generated client code + config + a hosted studio, gleamunison decomplects into ordinary handler composition — data over codegen, composition over configuration.
* **Verdict**: **Adopt (High Priority)**. This is the keystone; every other concept hangs off it.

### Concept B: Schema-Aligned Parsing (SAP)
* **BAML concept**: liberal-in-what-you-accept parser that repairs near-miss model output into the target type.
* **Gleamunison benefit**: A `gleamunison/sap` module: tokenize, strip prose, fix trailing commas/quotes, coerce literals, then validate against the core `Type`. Pure function, property-testable with the existing dogfood harness.
* **Verdict**: **Adopt (High Priority)**. Without SAP, LLM functions are demo-ware; with it, they're production.

### Concept C: Content-addressed prompts
* **BAML concept**: prompts are strings in `.baml` files, versioned by git.
* **Gleamunison benefit**: prompts become definitions in the Merkle DAG. Consequences BAML cannot replicate: hash-pinned prompt rollout (swap root hash = atomic prompt deploy), A/B by hash, prompt libraries synced to peers conflict-free, and a prompt's hash doubles as its audit identity in traces. This is the **Unison thesis applied to prompt engineering** — the strongest differentiator in this whole analysis.
* **Verdict**: **Adopt (High Priority)**. Nearly free on existing machinery; pure gleamunison advantage.

### Concept D: Type-directed schema emission
* **BAML concept**: `{{ ctx.output_format }}` injects a token-optimized schema description.
* **Gleamunison benefit**: types are computed metadata; write a `type -> prompt-schema` printer (BAML-style compact encoding, not JSON Schema). One pure function over existing type definitions.
* **Verdict**: **Adopt (Medium Priority)**. Low complexity, immediate token savings.

### Concept E: Evals, testsets, trace replay
* **BAML concept**: `test` blocks, testsets, eval pipelines; recorded LLM traces.
* **Gleamunison benefit**: extend the playbook/dogfood runner with an LLM mode: fixtures are content-addressed (deterministic replay by hash), the trace inspector captures live calls, and the mock handler replays them. Evaluation becomes another conformance level family.
* **Verdict**: **Adopt (Medium Priority)**. Infrastructure is 80% built.

### Concept F: Agent code discovery (`describe`) over datalog
* **BAML concept**: `baml describe` gives agents an AST-aware map of the codebase.
* **Gleamunison benefit**: the codebase is already a Merkle DAG and there is already a native datalog engine with BM25 + vector search. `describe` = index definitions into EAVT + expose a query builtin. Semantic code search for agents, self-hosted, content-addressed.
* **Verdict**: **Adopt (Medium Priority)**. Cheap, and compounds with Concept C (agents discovering *tools* by hash).

### Concept G: Semantic streaming of partial structures
* **BAML concept**: stream partial, type-safe objects with per-field completion guarantees.
* **Gleamunison benefit**: token stream → incremental SAP → process mailbox; consumers `recv` partial terms. Real but substantial work (incremental parser + partial-type semantics).
* **Verdict**: **Defer**. Land A–C first; streaming without SAP repairs garbage faster.

### Concept H: Multimodal types
* **Verdict**: **Defer**. Opaque `Media` type + base64 jet when a real use case demands it.

### Concept I: Host-language SDK codegen
* **Verdict**: **Decline**. Complects the artifact with every host ecosystem. The escript + Erlang distribution *is* the adoption story; Hickey would not trade one runtime for five code generators.

---

## 3. Complexity vs. Utility

| Element | Complexity | Utility | Recommendation |
|---|---|---|---|
| A: `LLM` ability + provider handlers | Medium | High | **Recommended** — keystone. |
| B: SAP module | Medium | High | **Recommended** — production gate. |
| C: Content-addressed prompts | Low | High | **Recommended** — differentiator, mostly wiring. |
| D: Type → schema printer | Low | Medium | **Recommended**. |
| E: LLM evals on playbook harness | Medium | Medium | **Recommended** after A–B. |
| F: `describe` over datalog | Low | Medium | **Recommended** — cheap agent-ergonomics win. |
| G: Semantic streaming | High | Medium | **Defer**. |
| H: Multimodal types | Medium | Low | **Defer** until demanded. |
| I: SDK codegen | High | Low | **Decline**. |

---

## 4. Actionable Path

1. **`gleamunison/llm` ability**: `complete`, plus jets for OpenAI/Anthropic-shaped HTTP via existing `http_client`; provider config through existing `gleamunison/config`.
2. **Retry/fallback handlers**: handler composition, not a client registry — prove the decomplected design on two providers.
3. **`gleamunison/sap`**: tolerant parser → validate against core `Type`; property tests via dogfood runner.
4. **Prompt definitions**: template-backed prompt terms in the codebase DAG; hash-pinned deployment; extend trace inspector to record LLM call/response by prompt hash.
5. **`type -> prompt-schema` printer** (BAML-style compact encoding).
6. **LLM eval family** in the playbook runner with content-addressed fixtures.
7. **`describe` builtin**: datalog/BM25/vector over the definition DAG for agent code discovery.

## 5. Bottom line

BAML v1 is betting that agents need a *new language*. Gleamunison's counter is that agents need a *better runtime*: one where prompts, tools, and evals are content-addressed, hot-swappable, distributable by hash, and where the LLM itself is just another effect you can handle, mock, and compose. Gaps A–C close the functional distance; C and F are leads BAML structurally cannot follow without becoming content-addressed itself.
