# gleamunison

**Content-addressed language runtime on the BEAM, built in Gleam.**

A working implementation of a Unison-style content-addressed programming
language: a definition is identified by the hash of its structure, compiled on
demand to BEAM bytecode, and loaded into a running VM by hash. Not a filename,
not a module path, not a package — the hash *is* the identity.

- **Version:** 3.24.0
- **Suite:** 508 tests, 0 failures
- **CI:** Erlang/OTP 27, 28, 29 × Ubuntu, macOS — all legs green
- **Classification:** `authenticated-single-node-service`
  ([verification witness](docs/verification/production-boundaries-2026-10-20.md))

## Status: what this is, and what it is not

The honest framing matters more than the marketing. This runtime is a serious
content-addressed execution platform with a strong identity model. It is **not**
a safe place to run arbitrary untrusted code, and it does not claim to be.

| Capability | State |
|---|---|
| Content-addressed identity (SHA256 of term + type) | Implemented, verified |
| Hash → compile → load → execute pipeline | Implemented, verified |
| Hindley-Milner type inference, two-phase elaboration | Implemented |
| Algebraic effects (stack-based handler frames) | Implemented |
| Content-addressed store (DETS / ETS / Mnesia) | Implemented |
| Pull-based sync: TCP protocol **v2** (HMAC handshake) + Erlang distribution | Implemented |
| HTTP + MCP service with bind gate, request auth, readiness probes | Implemented, single node |
| Evaluation budgets (wall clock, reductions, memory) | Implemented |
| Evidence signing, trust policy, key rotation/revocation | Implemented |
| LLM budgets, cancellation, transcript redaction | Implemented |
| **OS/container isolation for untrusted code** | **Not implemented** — requires an external executor |
| **TLS / mTLS transport encryption** | **Not implemented** — bind gate + token auth only |
| **Signed packages / attestations with revocation** | Partial — evidence signing only |
| **Live process migration** | Design only |
| **Multi-node clustering in production** | Not claimed — single authenticated node |

The `untrusted-execution` deployment profile is deliberately **disabled** in the
codebase: it refuses to admit work until a real OS-level sandbox exists.

## Rationale & Gap Analysis

### Why Gleamunison?

Gleamunison combines the type-safe concurrency of the BEAM (via Gleam) with
Unison's content-addressed codebase and algebraic effects, enabling zero-downtime
hot upgrades and dynamic sandboxing.

### Feature Set Differences (Gleamunison vs Unison)

| Feature | Unison | Gleamunison | Trade-off / Benefit |
|---|---|---|---|
| **Identity** | SHA3-512 (Term+Type) | SHA256 (Term+Type) | SHA256 is native on BEAM; less hash size overhead. |
| **Primitives** | `##` Prefix Namespace | Genesis Block (Hash space) | Genesis eliminates dual-identity complexity. |
| **Effect Model** | Explicit continuation `k` | Implicit stack-based frame | Stack-based is simpler; lacks explicit `k` resume. |
| **Codebase Store** | SQLite / Event Log | DETS / ETS / Mnesia | Native and lightweight on BEAM. |
| **Namespaces** | Hierarchical Projects | Flat namespace mapping | Flat is simpler; hierarchy can be layered. |

### Complexity vs. Utility

| Element | Complexity | Utility | Recommendation |
|---|---|---|---|
| Genesis Primitives | Low | High | **Adopted**: kept hash-space uniform. |
| Stack-based Effects | Medium | High | **Adopted**: simpler runtime implementation. |
| Unique Type GUIDs | Low | Medium | **Adopted**: prevents structural hash collisions. |
| Remote Ability | High | Low | **Out of scope**: rely on BEAM distribution instead. |

## How Hashes Act as Executables

A program is not a monolithic binary. It is a **Merkle DAG** of
content-addressed AST definitions stored in a codebase.

### The Merkle DAG code structure

Each definition is parsed into an AST and hashed on its structure, stripping
variable names to ensure α-equivalence. References to other definitions are
stored as hashes (`RefTo` nodes), so the graph is content-addressed all the way
down.

```
                  ┌───────────────────────┐
                  │   start-server Hash   │  ◄─── This single Root Hash IS the executable
                  │       [#ff45e8]       │
                  └───────────┬───────────┘
                              │
             ┌────────────────┴────────────────┐
             ▼                                 ▼
 ┌───────────────────────┐         ┌───────────────────────┐
 │  page-template Hash   │         │    query-db Hash      │
 │       [#ac88b2]       │         │       [#3b12ef]       │
 └───────────────────────┘         └───────────┬───────────┘
                                               │
                                               ▼
                                   ┌───────────────────────┐
                                   │  Datalog-Transact Jet │
                                   │  [#00000064] (Builtin)│
                                   └───────────────────────┘
```

### Step-by-step execution

1. **DAG resolution** — the runtime looks up the root hash, walks the dependency
   graph transitively, and fetches missing dependencies from peers over the sync
   protocol (TCP v2 with an HMAC challenge-response handshake, or Erlang
   distribution).
2. **On-the-fly compilation** — resolved AST nodes compile to BEAM bytecode in
   modules named after their hashes (e.g. `m_ff45e8`).
3. **Dynamic loading** — the VM loads the binary with `code:load_binary/3` and
   calls the entrypoint `'m_ff45e8':'$eval'()`.

This is what enables zero-downtime upgrades (swap to a new root hash) and
conflict-free dependency resolution (identity is the hash, so there are no name
collisions to resolve).

## What works today

These are implemented and exercised by the suite or the playbook — not
aspirations.

- **Zero-downtime hot upgrades.** Compile new logic to a new hash-named module
  and swap the root hash; existing processes keep their state. Hash-named
  modules mean no `code:purge` collisions with the old version.
- **Content-addressed distribution.** Nodes exchange root hashes and pull only
  missing definitions, so patching is incremental by construction.
- **Effects as authority.** File, network, time, and randomness operations go
  through abilities; the host decides what a handler is allowed to do. This is
  how evaluation is sandboxed today — at the effect layer, in a bounded process.
- **Bounded evaluation.** Every evaluation runs in a scope process with a wall
  clock deadline, a reduction ceiling, and a memory ceiling. Descendant process
  trees are owned and drained on timeout rather than leaked.
- **Supervised services.** HTTP and MCP run under supervisors with graceful
  drain; readiness reports storage, supervisors, and queues, and returns 503
  when any of them is unhealthy.
- **Reproducible verification.** Tests, evidence, and trace capture are
  content-addressed: evidence binds to definition hashes, so a claim of "this
  passed" names exactly which code passed.
- **Self-hosted Datalog.** The database engine is written in Gleamunison's own
  language (13 `.lisp` modules under `gleamunison_datalog/src/`), not in Gleam —
  the runtime dogfoods itself.
- **Agent interfaces.** MCP server, LSP server, and an HTTP API for eval,
  definitions, traces, modules, and observability.

### Designed, not implemented

Named here so nobody plans around them by accident:

- Live process migration (serialize a continuation, ship it, resume remotely).
- OS-level sandbox for third-party code (`untrusted-execution` profile).
- Signed package distribution with identity and revocation.
- Multi-tenant isolation across trust domains.

## Production boundaries

v3.24.0 closed the operational gaps that separated "implemented" from
"operable". Each boundary has one policy module, one owner, and a proof.

| Boundary | Enforcement | Documentation |
|---|---|---|
| **Bind / profile** | `GLEAMUNISON_BIND_ADDRESS` + `GLEAMUNISON_PROFILE`; non-loopback binds require an explicit profile | [deployment profiles](docs/operations/deployment-profiles.md) |
| **Request auth** | `GLEAMUNISON_HTTP_TOKEN` gates data routes; constant-time compare | [deployment profiles](docs/operations/deployment-profiles.md) |
| **Sync transport** | TCP protocol **v2**: HMAC challenge-response, replay table, per-peer token | [deployment profiles](docs/operations/deployment-profiles.md) |
| **Execution budget** | Wall clock (`GLEAMUNISON_EVAL_TIMEOUT_MS`), reductions, memory (`GLEAMUNISON_MAX_MEMORY_MB`) | [ADR-0067](docs/adr/0067-production-boundaries.md) |
| **Trust / keys** | Key state (active/revoked), trust policy, evidence signing (`GLEAMUNISON_EVIDENCE_SIGNING_KEY`) | [trust and key rotation](docs/operations/trust-and-key-rotation.md) |
| **Resources / observability** | Bounded HTTP/MCP/SSE concurrency, mailboxes, trace retention; `/api/ready`, `/api/live`, `/api/observability` | [observability](docs/operations/observability.md) |
| **LLM calls** | Token/cost budgets, concurrency cap, circuit breaker, cancellation, transcript redaction | [LLM policy](docs/operations/llm-policy.md) |
| **Compatibility** | Schema version (`schema-version`), upgrade and rollback gates | [compatibility](docs/operations/compatibility.md), [upgrade and rollback](docs/operations/upgrade-and-rollback.md) |

Everything above is verified by `scripts/verify_production_boundaries.clj`, which
runs the full battery and writes a machine-readable witness to
`docs/verification/`.

**Explicitly not claimed:** transport encryption (no TLS), OS-level isolation,
package signing, and multi-node trust. Deployments that need those must supply
them at the infrastructure layer.

## Project state

Measured, not asserted — the numbers below come from the tree and the suite at
v3.24.0.

| Metric | Value |
|---|---|
| Tests | 508 passing, 0 failures |
| Test suites | 85 files under `test/` |
| Playbook levels defined | 1,172 across 40 playbook docs |
| Gleam modules | 100 (93 in `src/gleamunison/`, 7 top-level) |
| Erlang modules | 43 production (plus 53 genesis `m_*.erl`) |
| Datalog engine | 13 self-hosted `.lisp` modules |
| ADRs | 68 |
| Escript | ~1.3 MB standalone |

| Pipeline step | Status |
|---|---|
| AST → hash (SHA256) | ✓ Content-addressed identity |
| Codebase insert with hash verification | ✓ DETS/ETS/Mnesia, dedup |
| Compile to BEAM (all Term variants) | ✓ Int/Float/Text/List/Lambda/Apply/Let/Match |
| Load into VM (`code:load_binary/3`) | ✓ OTP 27–29 |
| Type inference | ✓ Hindley-Milner style |
| Elaboration (surface → core) | ✓ Two-phase with name resolution |
| Effects runtime (process-dict stack) | ✓ do / handle / push / pop |
| Sync | ✓ TCP v2 (HMAC) + Erlang distribution |
| Native Datalog | ✓ Self-hosted, temporal, rules, BM25, vector |
| Escript | ✓ ~1.3 MB, Erlang/OTP only at runtime |

## Modules

100 Gleam modules, 43 production Erlang modules, 53 genesis `m_*.erl` modules,
and 13 self-hosted Datalog modules. Grouped by concern:

| Area | Key modules |
|---|---|
| **Identity & AST** | `identity`, `ast`, `types`, `definition_codec` |
| **Parsing & elaboration** | `lexer`, `parser`, `elaborate`, `elab_def`, `elab_term`, `elab_types`, `elab_pat`, `elab_ctx`, `lower` |
| **Types** | `inference`, `infer_helper`, `typecheck`, `type_pretty` |
| **Compilation & loading** | `compile`, `loader`, `pipeline`, `jets` |
| **Codebase & storage** | `codebase`, `codebase_index`, `storage`, `namespace` |
| **Effects & capabilities** | `effects`, `capability`, `turnstile` |
| **Policy & trust** | `auth`, `trust`, `sandbox_policy`, `cancellation`, `evidence` |
| **Services** | `http`, `http_client`, `mcp`, `mcp_server`, `mcp_session`, `lsp`, `lsp_features`, `lsp_types`, `health`, `metrics` |
| **LLM integration** | `llm`, `llm_types`, `llm_wire`, `llm_budget`, `llm_controls`, `llm_middleware` |
| **Sync** | `sync`, `sync_types`, `gleamunison_tcp_sync.erl`, `gleamunison_peer.erl` |
| **REPL & CLI** | `repl`, `repl_eval`, `repl_io`, `repl_graph`, and 16 `cli_*` modules |
| **Testing & verification** | `test_runner`, `verify`, `transcript`, `prompt`, `rank`, `manifest` |
| **Genesis** | `genesis`, `bootstraps`, plus 53 `m_*.erl` modules |
| **Datalog** | 13 self-hosted `.lisp` modules: core, index, transact, schema, query, aggregate, pull, temporal, rules, graph, vector, bm25, actor |

## Toolchain and CI

Kept in lockstep with the CI matrix:

| Component | Version |
|---|---|
| Gleam | 1.19.1 |
| Erlang/OTP | 27, 28, 29 (all tested) |
| rebar3 | 3 |

Every push runs the full matrix on Ubuntu and macOS for each OTP version:
`gleam deps download`, `gleam test`, `gleam format --check src test`, plus a
release-gates job that builds the escript and checks the artifact contract.

```sh
gleam test                                    # 508 tests
gleam format --check src test                 # formatting gate
./build_escript.sh                            # standalone artifact
bb scripts/run_playbook_tests.clj             # playbook conformance (1,172 levels)
bb scripts/verify_production_boundaries.clj   # full boundary gate + witness
```

## Quick start

```sh
git clone https://github.com/moneyacademyKE/gleamunison.git
cd gleamunison
gleam deps download
./build_escript.sh
./gleamunison_escript repl        # interactive REPL
./gleamunison_escript server 8080 # HTTP API
gleam test                        # run the suite
```

## CLI

```
gleamunison <command>

  server [port]          start the web server (default 8080)
  repl                   interactive REPL (optionally preload a .lisp file)
  verify [file]          verify a scratch file
  llm <provider> <prompt> call an LLM (openai | anthropic)
  mcp [port] [--load f]  MCP server for agents (default 8099)
  all                    run all available levels
  schema-version         print the storage/codec schema version
  levelN                 run playbook level N
```

## HTTP API

Data routes are gated by `GLEAMUNISON_HTTP_TOKEN` when set. Readiness and
liveness are always available for orchestrators.

| Route | Purpose |
|---|---|
| `POST /eval`, `POST /define` | Evaluate or install a definition |
| `GET /browse`, `GET /counter` | Inspect the codebase |
| `POST /mcp` | MCP over HTTP |
| `GET /api/status`, `/api/events`, `/api/processes`, `/api/sync-status` | Runtime state |
| `GET /api/logs`, `/api/modules`, `/api/traces`, `/api/traces/:id` | Observability |
| `GET /api/health`, `/api/observability` | Detailed health and resource report |
| `GET /api/ready`, `/api/live` | Readiness (503 when unhealthy) and liveness |

## Why the escript is only ~1.3 MB

The standalone binary contains the full runtime — parser, elaborator,
typechecker, compiler, loader, codebase, effects system, web server, REPL, 53
genesis modules, and dependencies — in about 1.3 MB, because:

**BEAM bytecode is dense.** The compiled `.beam` files are a few MB
uncompressed; zip compression brings the artifact to ~1.3 MB.

**No VM bundled.** Unlike Go or Rust binaries that statically link a runtime, the
escript relies on the system Erlang/OTP installation. The artifact itself is a
zip archive with a small launcher header.

| Format | Size | Dependencies |
|---|---|---|
| gleamunison escript | **1.3 MB** | Erlang/OTP |
| Go binary | 10–20 MB | None |
| Rust binary | 5–15 MB | None |
| Node.js app + deps | 100–500 MB | Node.js |

If Erlang/OTP is already installed, this is close to a zero-install language
runtime.

## Documentation

- [Playbook](docs/PLAYBOOK.md) — how to work on this project
- [Architecture](docs/ARCHITECTURE.md) — design deep dive
- [Roadmap](docs/ROADMAP.md) — phase plan from spec to production
- [Operations Runbook](docs/OPERATIONS.md) — deploy, configure, monitor, upgrade
- [Deployment profiles](docs/operations/deployment-profiles.md) — bind gate, auth, trust levels
- [Observability](docs/operations/observability.md) — readiness, metrics, trace retention
- [Trust and key rotation](docs/operations/trust-and-key-rotation.md) — evidence keys, revocation
- [LLM policy](docs/operations/llm-policy.md) — budgets, cancellation, redaction
- [Compatibility](docs/operations/compatibility.md) — schema versions and migration
- [Upgrade and rollback](docs/operations/upgrade-and-rollback.md) — artifact gates
- [Verification matrix](docs/operations/verification-matrix.md) — what each gate proves
- [Verification witness](docs/verification/production-boundaries-2026-10-20.md) — the machine-readable proof
- [ADRs](docs/adr/) — 68 Architecture Decision Records
- [Learnings](docs/LEARNINGS.md) — architectural insights discovered
- [Patterns](docs/PATTERNS.md) — design patterns used
- [Reference Manual](docs/MANUAL.md) — complete user guide

## License

MIT
