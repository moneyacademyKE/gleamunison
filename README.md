# gleamunison

**Content-addressed language runtime on the BEAM, built in Gleam.**

A working implementation of a Unison-style content-addressed programming
language: a definition is identified by the hash of its structure, compiled on
demand to BEAM bytecode, and loaded into a running VM by hash. Not a filename,
not a module path, not a package — the hash *is* the identity.

- **Version:** 3.24.0
- **Suite:** 649 tests, 0 failures
- **CI:** Erlang/OTP 27, 28, 29 × Ubuntu, macOS — matrix configured; local receipts are not a substitute for every hosted leg
- **Classification:** `authenticated-single-node-service`
  ([verification witness](docs/verification/production-boundaries-2026-10-24.md))

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
| Evidence signing and trust policy | Enforced at `publish`, `pkg install` and `run`; the production environment accepts one configured signer; multi-key overlap is library-only |
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

1. **DAG resolution** — the runtime looks up the root hash and walks the dependency
   graph in the selected local store and branch namespace. Missing content must be
   transferred explicitly with `sync` or `pkg --peer` before `run`; execution does
   not fetch from peers implicitly.
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
| Tests | 649 passing, 0 failures |
| Test suites | 105 files under `test/` |
| Playbook levels defined | 934 executable passes plus 238 explicit exclusions in the default run |
| Gleam modules | 109 (102 in `src/gleamunison/`, 7 top-level) |
| Erlang modules | 46 production (plus 53 genesis `m_*.erl`) |
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

109 Gleam modules, 46 production Erlang modules, 53 genesis `m_*.erl` modules,
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
| **Services** | `http`, `http_client`, `mcp`, `mcp_server`, `mcp_session`, `lsp`, `lsp_features`, `lsp_types`, `readiness` |
| **LLM integration** | `llm`, `llm_types`, `llm_wire`, `llm_budget`, `llm_controls`, `llm_middleware` |
| **Sync** | `sync`, `sync_types`, `gleamunison_tcp_sync.erl`, `gleamunison_peer.erl` |
| **REPL & CLI** | `repl`, `repl_eval`, `repl_io`, `repl_graph`, and 16 `cli_*` modules |
| **Testing & verification** | `test_runner`, `verify`, `transcript`, `rank`, `manifest` |
| **Genesis** | `genesis`, `bootstraps`, plus 53 `m_*.erl` modules |
| **Datalog** | 13 self-hosted `.lisp` modules: core, index, transact, schema, query, aggregate, pull, temporal, rules, graph, vector, bm25, actor |

### Library and CLI boundaries

Four modules remain intentionally library-first: `sap`, `patch`, `prompt`, and
`schema_printer` are published, compiled, and tested but are not CLI routes.
`trust` is different: production `publish`, `pkg install`, and `run` call its
policy gate; its multi-key overlap constructor remains a library/test surface.

| Module | What it provides | Wired into the runtime? |
|---|---|---|
| `gleamunison/trust` | Key states (active/revoked/expired) and rotation windows | Yes for production `publish`, `pkg install`, and `run`; multi-key overlap remains library/test-only |
| `gleamunison/sap` | Schema-aligned parsing of near-miss model output (fences, trailing commas, Python literals) | No — the LLM CLI expects well-formed JSON |
| `gleamunison/patch` | Named, content-addressed update propagation | No |
| `gleamunison/prompt` | Content-addressed prompts as definitions | No |
| `gleamunison/schema_printer` | Type → compact prompt schema | No |

`sandbox_policy` **is** wired: `/eval` and `/define` admit through it, and the
`untrusted-execution` profile refuses with `403 missing_external_executor`.

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
gleam test                                    # 649 tests
gleam format --check src test                 # formatting gate
./build_escript.sh                            # standalone artifact
bb scripts/run_playbook_tests.clj             # 934 passes + 238 explicit exclusions
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
  publish <file.lisp>    publish definitions behind the evidence gate
  unpublish <name>       retract a name: index line, binding, and bytes
  purge <hash> [--yes]   remove a definition and the deps only it kept alive
  log [content|exec|all]  what the store has seen (--tail N)
  test <file.lisp>       run the test forms in a file
  run <content-hash>     run a definition from the store, by hash
                         [args...] [--json] [--inspect] [--store path]
                         [--branch name] (default: main)
  llm <provider> <prompt> call an LLM (openai | anthropic)
  mcp [port] [--load f]  MCP server for agents (default 8099)
  all                    run all available levels
  schema-version         print the storage/codec schema version
  levelN                 run playbook level N
```

### Definitions are the program

`publish` admits a definition only after its evidence gate passes, and admission
puts the definition *itself* in the content-addressed store: the bytes are
inserted under their content hash and the name is bound to that ref on the
branch namespace. From then on the definition is fetchable and runnable by
identity:

```
gleam run -- test lib.lisp         # evidence attaches to content hashes
gleam run -- publish lib.lisp      # admitted: bytes stored, names bound
gleam run -- run <hash>            # executes it, dependencies first
gleam run -- run <hash> 40 2       # a function takes its declared arity
gleam run -- run <hash> 40 2 --json # {"ref":"…","value":42}
gleam run -- run <hash> --inspect  # module, arity, exports: does NOT call
gleam run -- unpublish <name>      # retract the name (refuses if in use)
gleam run -- purge <hash>          # dry run: what would go, and why
gleam run -- purge <hash> --yes    # remove it and its exclusive deps
gleam run -- log content           # what entered the store, oldest first
gleam run -- log exec --tail 50    # execution attempts and their outcomes
gleam run -- log all               # both, in one chronological view
```

`--json` and `--inspect` are different questions. `--json` always executes and
changes only how the result is rendered; `--inspect` is the only mode that does
not execute — it loads the module to read its export table and never applies
`'$eval'`. One flag cannot mean two things depending on arity.

`run` resolves the dependency closure before executing, so a stored definition
that calls another stored definition works with no source on disk. Dependencies
are referenced by name ref, which is why the namespace binding matters; builtin
names (`+`, `eq?`) come from the baseline environment, the same one the REPL
establishes. A ref the store does not hold fails with the missing hash instead
of pretending to run.

Retraction is the reverse of admission, and it removes all three facts a name
stands on: the index line, the namespace binding, and the bytes. `unpublish`
refuses rather than half-finishing — if another stored definition depends on
the content, or another name still binds it, nothing is removed and the message
names what stands in the way.

`purge` works by content hash instead of by name, and it is a dry run until
`--yes`: it prints the removal set (the definition plus every stored dependency
that nothing outside the set uses) and changes nothing. Both commands refuse
when something outside the set depends on the ref, because a store that loses
the thing its definitions call is a store that lies about being runnable.

### The store keeps its own logs

Two append-only logs sit beside the store file, both durable across restarts:

| Log | Written by | Records |
|---|---|---|
| `content_log.dets` | admission: `publish` and `sync` | what entered the store, and when |
| `exec_log.dets` | execution: `run` | every attempt: `ok` or `refused`, the reason, the caller |

`log all` merges them into one chronological view. `pkg install` adds no content
— it installs what the store already holds — so it writes no content entry.

They are separate from the store on purpose. The store is content-addressed and
immutable; a log is time-ordered. Writing a changing fact into the store would
put it behind a hash that cannot change. The execution log records refusals
too, because the attempt you need to see is the one that did not happen.

### What admits content

Three paths write to the store, and each has exactly one gate:

| Path | Gate | What it proves |
|---|---|---|
| `publish` | evidence turnstile | every definition carries a passing attestation |
| `sync` | content addressing | the bytes hash to the ref they arrived under |
| `pkg install` | evidence turnstile | the manifest's definitions are attested |

`sync` is not an unguarded door: `accept_chunk` refuses a chunk whose bytes do
not hash to its ref, and refuses a conflicting chunk for a ref already held
(`HashConflict`). A peer cannot name its bytes something they are not, because
the name *is* the hash. What `sync` does not re-check is *evidence* — it moves
content, not claims — which is why `run` re-checks the evidence gate at the
moment of execution rather than trusting that admission happened. The gate you
can rely on is the one at the point of use.

| Exit | Meaning |
|---|---|
| 0 | the value rendered on stdout |
| 1 | refused: wrong arity, no verified evidence, not a runnable term |
| 2 | unresolvable: absent from the store, unreadable, or a malformed hash |

Errors go to stderr, so stdout carries only the result: `run … | jq` works.
`run` executes verified content by default; `GLEAMUNISON_STORE_ALLOW_UNVERIFIED=1`
is the explicit hatch for local work and warns on stderr.
`GLEAMUNISON_STORE_DIR` points every command at another store directory (the
index lives beside it), which is how a test or CI run keeps its own.

## HTTP API

Data routes are gated by `GLEAMUNISON_HTTP_TOKEN` when set. Readiness and
liveness are always available for orchestrators.

| Route | Purpose |
|---|---|
| `GET /eval?expr=`, `GET /define?name=&expr=` | Evaluate or install a definition |
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
- [Verification witness](docs/verification/production-boundaries-2026-10-24.md) — the machine-readable proof
- [ADRs](docs/adr/) — 68 Architecture Decision Records
- [Learnings](docs/LEARNINGS.md) — architectural insights discovered
- [Patterns](docs/PATTERNS.md) — design patterns used
- [Reference Manual](docs/MANUAL.md) — complete user guide
- [Archive](docs/archive/README.md) — superseded analyses and walkthroughs, kept for the record

## License

MIT
