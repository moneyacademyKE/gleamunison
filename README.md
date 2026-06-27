# gleamunison

**Content-addressed language runtime on the BEAM, built in Gleam.**

A running prototype of a Unison-style content-addressed programming language
that compiles to BEAM bytecode and loads dynamically into the Erlang VM.

## Project State

**Running prototype (Phase 0 complete).** All 6 components are implemented:

| Step | Status |
|---|---|
| AST → Hash (phash2) | ✓ Content-addressed identity |
| Codebase insert with hash verification | ✓ In-memory, dedup |
| Compile to BEAM binary (all Term variants) | ✓ Int/Float/Text/List/Lambda/Apply/Let/Match |
| Load into VM (`code:load_binary/3`) | ✓ OTP 29 compatible |
| Type inference (Int/Float/Text/List) | ✓ Hindley-Milner style |
| Elaboration (Surface → Core) | ✓ Two-phase with name resolution |
| Effects runtime (process dict stack) | ✓ do_/handle_/push_frame/pop_frame |
| Sync protocol (pull-based) | ✓ Types + Erlang distribution FFI stubs |
| escript standalone binary | ✓ 593KB, no Gleam dependency at runtime |

## Why the escript is only 593 KB

The standalone binary (`gleamunison_escript`) contains the full content-addressed runtime — parser, elaborator, typechecker, compiler, loader, codebase, effects system, web server, REPL, 50 genesis modules, and all stdlib dependencies. At 593 KB, it's compact because:

**BEAM bytecode is dense.** The 113 compiled `.beam` files are ~1.2 MB uncompressed; zip compression brings that to ~590 KB.

**No VM bundled.** Unlike Go or Rust binaries that statically link a runtime, the escript relies on the system's Erlang/OTP installation (~150 MB, installed once). The escript itself is just a zip archive with a 50-byte launcher header.

| Format | Size | Dependencies |
|---|---|---|
| gleamunison escript | **593 KB** | Erlang/OTP |
| Go binary | 10–20 MB | None |
| Rust binary | 5–15 MB | None |
| Node.js app + deps | 100–500 MB | Node.js |

If you already have Erlang installed, this is as close to a zero-install language runtime as it gets.

## Modules (17 source modules, 1,650+ lines)

| Module | Concern | Status |
|---|---|---|
| `gleamunison/identity` | Opaque Hash, DefinitionRef, LocalVar | Real |
| `gleamunison/ast` | Core AST: Term (12 variants), Type, Definition, Unit | Real |
| `gleamunison/types` | Type inference + cache | Real |
| `gleamunison/codebase` | Content-addressed Merkle store | Real |
| `gleamunison/elaborate` | Surface → Core with name/ability resolution | Real |
| `gleamunison/elab_def` | Elaboration helper for definitions (term, type, ability) | Real |
| `gleamunison/lower` | Lowering surface types to core type references | Real |
| `gleamunison/parser` | S-expression parser & tokenizer | Real |
| `gleamunison/compile` | AST → Erlang source → BEAM binary | Real |
| `gleamunison/loader` | Dynamic module loading into VM | Real |
| `gleamunison/effects` | Algebraic effect types + Erlang runtime | Real |
| `gleamunison/storage` | ETS, DETS, and Partitioned DETS storage adapters | Real |
| `gleamunison/repl` | REPL entry point and loop orchestrator | Real |
| `gleamunison/repl_eval` | REPL evaluation and definition compiler pipeline | Real |
| `gleamunison/repl_io` | REPL bracket counter and line accumulator | Real |
| `gleamunison/sync` | Pull-based sync protocol | Real |
| `gleamunison/http` | Web server entry point | Real |
| `gleamunison_ffi.erl` | FFI: hashing, compilation, loading, process dict | Real |
| `gleamunison_effets.erl` | Effects runtime: push/pop/find_frame, do_op/handle_comp | Real |


## Quick start

```sh
cd ~/Desktop/gleamunison
gleam run        # Run the full pipeline demonstration
gleam test       # Run tests
./gleamunison    # Standalone escript (after ./build_escript.sh)
```

## Documentation

- [Playbook](docs/PLAYBOOK.md) — how to work on this project
- [Architecture](docs/ARCHITECTURE.md) — deep dive into the design
- [Roadmap](docs/ROADMAP.md) — 6-phase plan from spec to production
- [Learnings](docs/LEARNINGS.md) — architectural insights discovered
- [Patterns](docs/PATTERNS.md) — design patterns used
- [Reference Manual](docs/MANUAL.md) — complete reference user guide
- [ADRs](docs/adr/) — Architecture Decision Records

## Runtime output

```
=== Gleamunison ===
Int(42)           ✓ Hash → Compile → Load
Lambda(id)        ✓ Hash → Compile → Load
Apply(id, 99)     ✓ Hash → Compile → Load
Let(V0=42, V0)    ✓ Hash → Compile → Load
Text(hello)       ✓ Hash → Compile → Load
List([1,2,3])     ✓ Hash → Compile → Load
Match(42, cases)  ✓ Hash → Compile → Load
Type Inference    ✓ Int/Float/Text/List
Elaboration       ✓ Surface → typed
Effects           ✓ RuntimeConfig
Sync              ✓ PeerId/SyncState
```

## Unique Usecases (Impossible on Gleam or Unison Alone)

Gleamunison combines the scheduling, distribution, and runtime efficiency of the BEAM with the content-addressing and algebraic effects constraints of Unison:

1. **Zero-Downtime Stateful Actor Upgrades**: Hot-swapping active actor code on-the-fly without state loss. Standard Gleam module updates clash on name/version collisions, and Unison lacks native actor scheduling. Gleamunison addresses both.
2. **Decoupled Multi-tenant Sandboxing**: Running untrusted third-party plugins concurrently where namespaces are isolated by hash, and capabilities (like IO/network) are dynamically sandboxed by wrapping compilation thunks in algebraic effects `Handle` terms.
3. **Resilient P2P Job Stealing**: Edge computing nodes dynamically pulling (`pull_sync`), structurally verifying, local-compiling, and running job definitions securely.

## License

TBD
