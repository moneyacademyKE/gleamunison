---
name: gleamunison
description: Work with the gleamunison codebase — a content-addressed language runtime on the BEAM, built in Gleam. Use this skill when adding features, fixing bugs, writing dogfood levels, or understanding the architecture.
---

# Gleamunison Skill

## What is Gleamunison

gleamunison is a content-addressed language runtime with algebraic effects running on the Erlang BEAM, implemented in Gleam. It combines Unison-style content addressing (identity = SHA256 hash of AST + type), algebraic effects via process-dictionary handler stacks, and the BEAM as both target and constraint (hot code swapping, process isolation, OTP 29).

**Version**: 2.0.0
**Test suite**: 53 unit tests, 4235 real dogfood levels (v2-v83, levels 1-5320, 82 batches = 4288 total verifications, 0 failures)

## Codebase Structure

```
scripts/
  loop_infinite.clj     # v2 — zombie cleanup, retry detection, error alert
  dogfood_loop.clj      # Registration + verification helper
  rebuild_meta.clj      # Generates meta from v*.gleam files
  generate_levels.clj   # v2 — 24 templates, per-level imports, --count flag
src/

```
src/
  gleamunison/           # 40 Gleam modules — core runtime + stdlib
    ast.gleam            # Core AST: Term (15 variants), Type, Definition, Unit
    identity.gleam       # Hash, DefinitionRef, LocalVar, genesis builtins
    codebase.gleam       # Content-addressed store, hash_of_definition
    compile.gleam        # AST -> Erlang source -> BEAM binary
    loader.gleam         # Dynamic module loading with LRU eviction
    inference.gleam      # Hindley-Milner type inference
    types.gleam          # TypeCache, InferenceError, validate_handler
    elaborate.gleam      # Surface -> Core elaboration orchestration
    elab_term.gleam      # Term elaboration (15 surface variants -> core)
    elab_types.gleam     # Surface types, ElaborateError, SurfaceDef
    elab_def.gleam       # Definition elaboration (term/type/ability)
    elab_pat.gleam       # Pattern elaboration
    elab_ctx.gleam       # Elaboration context (names, bindings, abilities)
    parser.gleam         # S-expression parser + tokenizer
    lexer.gleam          # Tokenizer (Symbol, IntVal, FloatVal, LParen, etc.)
    effects.gleam        # HandlerFrame, OpHandler, RuntimeConfig
    storage.gleam        # ETS/DETS/partitioned DETS/Mnesia adapters
    sync.gleam           # Pull-based sync protocol
    repl.gleam           # REPL loop, eval_string, eval_string_unique
    repl_eval.gleam      # REPL evaluation pipeline
    repl_io.gleam        # Bracket counter, line accumulator
    pipeline.gleam       # Factored pipeline phases
    lower.gleam          # Type lowering with de Bruijn indices
    typecheck.gleam      # Type checker with alpha-equivalence normalization
    type_pretty.gleam    # Pretty-printer for types (glam)
    infer_helper.gleam   # Type inference helpers (substitute, normalize)
    http.gleam           # Web server entry point
    http_client.gleam    # Typed HTTP client (get/post/put/delete)
    json.gleam           # JSON encode/decode
    datetime.gleam       # Opaque DateTime, ISO 8601
    filepath.gleam       # Opaque Path manipulation
    crypto.gleam         # SHA256/512, HMAC, random bytes
    template.gleam       # {{var}} string interpolation
    log.gleam            # Structured logging (debug/info/warn/error)
    config.gleam         # Configuration management (env/TOML/CLI)
    health.gleam         # Health checks and readiness probes
    metrics.gleam        # Counter/gauge/histogram
    jets.gleam           # FFI compiler jets
  dogfood.gleam          # All-levels dispatcher (Dict-based, stubs for gaps)
  dogfood_meta.gleam     # real_levels_list — wires real level functions
  dogfood_core.gleam     # Core dogfood levels (21-47)
  dogfood_bench.gleam    # Benchmark dogfood levels (48-55)
  dogfood_v2.gleam       # v1.1.0 feature levels (1001-1048)
  dogfood_v3.gleam       # Phase 2 levels (1049-1100)
  dogfood_v4.gleam       # Phase 3 levels (1101-1150)
  dogfood_v5.gleam       # Phase 4 levels (1151-1200)
  dogfood_v6.gleam       # Phase 5 levels (1201-1250)
  dogfood_v7.gleam       # Phase 6 levels (1251-1300)
  dogfood_v8.gleam       # Phase 7 levels (1301-1350)
  dogfood_v9.gleam       # Phase 8 levels (1351-1400)
  dogfood_v10.gleam      # Phase 9 levels (1401-1450)
  dogfood_v11.gleam      # Phase 10 levels (1451-1500)
  dogfood_v12.gleam      # Phase 11 levels (1501-1550)
  dogfood_v13.gleam      # Phase 12 levels (1551-1600)
  dogfood_v14.gleam      # Phase 13 levels (1601-1650)
  dogfood_v15.gleam      # Gap-fill: crypto, json, metrics (1651-1700)
  dogfood_v16.gleam      # HTTP server, health, effects, template (1701-1750)
  dogfood_v17.gleam      # Batch 17 levels (1751-1800)
  dogfood_v18.gleam      # Batch 18 levels (1801-1900)
  dogfood_v19.gleam      # Batch 19 levels (1901-2000)
  dogfood_v20.gleam      # Batch 20 levels (2001-2100)
  dogfood_v21.gleam      # Batch 21 levels (2101-2200)
  dogfood_v22.gleam      # Batch 22: jets, compile+load+eval, chains (2201-2270)
  dogfood_v23.gleam      # Batch 23: Handle, patterns, guards, storage (2271-2320)
  dogfood_v24.gleam      # Batch 24: cross-module RefTo, exec, REPL (2321-2370)
  dogfood_v25.gleam      # Batch 25-83: auto-generated by infinite loop (2371-5320)
  gleamunison.gleam      # Main entry point (CLI dispatch)
  gleamunison_*.erl      # 30+ Erlang FFI modules
  m_*.erl                # 52 genesis modules (content-addressed builtins)
test/                    # Gleam test files (13 files)
  gleamunison_test.gleam # Main test suite
  effects_test.gleam     # Effects runtime tests
  storage_test.gleam     # Storage adapter tests
  codebase_test.gleam    # Codebase hash tests
  elaboration_test.gleam # Elaboration tests
  inference_test.gleam   # Inference tests
  jets_test.gleam        # Jet integration tests
  sync_test.gleam        # TCP sync tests
  handler_test.gleam     # Handler validation tests
  migration_test.gleam   # Migration tests
  parser_snapshot_test.gleam  # Parser snapshot tests
  roadmap_tdd_test.gleam # TDD tests (LRU, stack corruption, spelling)
  round4_tdd_test.gleam  # Round 4 TDD tests
  gleamunison_ffi_test.erl   # Erlang FFI tests
docs/
  ROADMAP.md             # 12-phase roadmap
  ARCHITECTURE.md        # Architecture deep dive
  PLAYBOOK.md            # Development methodology
  MANUAL.md              # Reference manual
  OPERATIONS.md          # Deploy, configure, monitor, troubleshoot
  LEARNINGS.md           # 49 architectural insights
  PATTERNS.md            # 39 design patterns
  GLOSSARY.md            # Terminology reference
  LSP.md                 # LSP protocol spec
  CHANGELOG.md           # Release history
  adr/                   # 59 Architecture Decision Records
  playbook/              # 25 playbook files (batches 0001-2370)
  stdlib/index.html      # Standard library documentation
```

## Development Workflow (Playbook Methodology)

1. **Spec-first, implement second.** Every module starts as type definitions and function signatures. Implementation fills in `todo` values after the spec is stable.

2. **De-complection (Rich Hickey).** If two concerns can be separated, they must be separated. Every type and function signature is a binding contract.

3. **Dogfood-driven development.** Build progressively complex test apps organized as numbered levels in a playbook. Run each level to verify. Fix bugs encountered during testing. Extend the playbook as capabilities grow.

4. **Change process (Hickey loop):**
   a. Identify the gap
   b. Analyze what's complected
   c. Propose the fix
   d. Update all affected types and signatures
   e. Update documentation (ADRs, README, ARCHITECTURE)

## Key Conventions

### LOC Constraints
All Gleam/Erlang source files MUST be strictly under 250 LOC. If a module grows close to this limit, decompose it into high-cohesion, low-coupling sub-modules. Keep type definitions separated from logic files where necessary to avoid circular dependencies.

### Type Conventions
- `pub opaque type` for anything that must maintain invariants (Hash, Codebase, Loader, DateTime, Path)
- `pub type` for value types (Term, Definition, Type, HttpResponse)
- Functions return `Result(Ok, Error)` for fallible operations
- All error types are defined as custom types, never bare strings

### FFI Conventions
- FFI functions use `@external(erlang, "module_name", "function_name")` with named parameters
- Erlang FFI modules are files named `gleamunison_*.erl` in `src/`
- OTP 29 quirks: `compile:file/2` returns `{ok, Mod, []}`, use catch-all guards
- String representation: Gleam v1.0+ represents `String` as UTF-8 binaries. FFI must use `is_binary` guards, not `is_list`. Functions returning strings to Gleam must return binaries, not charlists.

### Import Conventions
- Never import the same module twice (causes "Duplicate import" error)
- To import both a module AND specific constructors from it, use a single import: `import gleamunison/config.{StringVal, load, get}`
- When using module-qualified access (`module.function()`), import the module directly: `import gleamunison/config`

### Module Naming
Content-addressed modules use the `m_` prefix followed by the last 8 hex characters of the hash (e.g., `m_e8e52932`). This prevents collisions with any Gleam module.

## Common Gotchas

### `bit_array.to_string/1` returns `Result`, not `String`
```gleam
// WRONG:  let s = bit_array.to_string(b)
// CORRECT: case bit_array.to_string(b) { Ok(s) -> s; _ -> "" }
```

### Erlang BIF name conflicts
Avoid naming module exports after Erlang BIFs: `apply/2`, `spawn/1`, `list_to_binary/1` shadow custom functions. Use alternatives: `adapt/2`, `start_task/1`, `to_bin/1`.

### Gleam case branches — no semicolons
Gleam v1.0+ removed semicolons. Case branches use only newlines:
```gleam
case x { Ok(s) -> s; Error(_) -> "" }        // WRONG
case x { Ok(s) -> s; _ -> "" }               // CORRECT
```

### Labeled constructor pattern matching
Custom types with labeled fields cannot be partially matched. Use wildcard `..`:
```gleam
// WRONG: ast.Lambda(binder: _, body) -> ...
// CORRECT: case term { ast.Lambda(..) -> let ast.Lambda(binder: _, body: b) = term ... }
```

### Opaque type field access
`pub opaque type` prevents field access from outside the defining module. Use accessor functions instead.

### Erlang charlist vs binary
Many Erlang stdlib functions return charlists (string lists), not binaries. Wrap with `list_to_binary/1`.

### ETS ordered_set requires tuple keys
`ordered_set` tables require tuple keys. A bare integer causes a `badarg` crash.

## Dogfooding

### How Levels Work
Each dogfood level is a public function `pub fn levelN() -> Nil` that exercises a specific runtime capability. Levels are organized by batch (50 levels per batch). There are 82 dogfood files (v2 through v83) covering 4235 real levels. Batches v25-v83 are auto-generated by the infinite dogfood loop using `scripts/generate_levels.clj` (21 template patterns cycled across 49 levels + 1 certification).

### Running the Infinite Loop
The infinite loop (`scripts/loop_infinite.clj`) runs in a terminal and autonomously:
1. Computes the next batch number and level range
2. Spawns `cmd -p "prompt" --yolo --skip-onboarding` with imperative commands
3. The AI agent generates levels, registers, builds, verifies, tests, and updates docs
4. When cmd exits, the loop repeats indefinitely

Usage:
```sh
bb scripts/loop_infinite.clj     # Start infinite loop
bb scripts/dogfood_loop.clj --register  # Rebuild meta from v*.gleam files
bb scripts/dogfood_loop.clj --verify    # Build all + run level70 certification
```

### Adding a New Level Manually
(Only needed for batches outside the auto-generator's template patterns)
1. Write the level function in the appropriate file
2. Register it in `dogfood_meta.gleam` -> `real_levels_list()`
3. Ensure the range in `dogfood.gleam` -> `all_levels()` covers the new level number
4. Test: `gleam run -- levelN`

### Running Levels
```sh
gleam run -- level2321    # Run a single level
gleam run -- all           # Run all 1-2370 (real + stubs)
gleam test                 # Run 53 unit tests
```

## Testing
- `gleam test` — runs 53 unit tests covering hashing, storage, parser, loader, effects, sync, elaboration, inference, jets, migration
- `gleam run -- levelN` — runs a specific dogfood level
- Each level prints `--- Level N: Description ---` header and `Level N: OK` on success
- Dogfood levels cover parse, elaborate, typecheck, compile, load, eval, Handle, cross-module RefTo, REPL API, storage adapters, large structures

## Common Operations

### Adding a New Gleam Module
1. Create `src/gleamunison/new_module.gleam`
2. If it needs Erlang FFI, create `src/gleamunison_new_module.erl`
3. Add to escript build script if it produces BEAM files
4. Build: `gleam build`
5. Test: add dogfood levels OR unit tests

### Adding a New AST Variant
1. Add variant to `ast.gleam` -> `pub type Term { ... }`
2. Add hashing case in `codebase.gleam` -> `fn hash_term(term)`
3. Add compilation case in `compile.gleam` -> `fn emit_term(t)`
4. Add inference case in `inference.gleam` -> `fn infer_term(term, cache)`
5. Add surface type in `elab_types.gleam` -> `pub type SurfaceTerm`
6. Add elaboration in `elab_term.gleam` -> `fn elaborate_term(term, ctx)`
7. Add parser support in `parser.gleam` -> `fn sexpr_to_term(sexpr)`
8. Update tests that construct the affected AST nodes

### Adding a New Feature to the REPL
1. Add surface syntax parsing in `parser.gleam`
2. Add elaboration in `elab_term.gleam`
3. Add compilation in `compile.gleam`
4. Add dogfood levels exercising the new feature
5. Update `repl.gleam` if new builtins are needed at REPL bootstrap

## Key Architectural Notes

### The Pipeline
```
S-expression text -> Parser -> SurfaceTerm -> Elaborator -> Core AST + Type
    -> Hasher (SHA256) -> DefinitionRef
    -> Compiler (Erlang source -> BEAM binary)
    -> Loader (code:load_binary/3)
    -> $eval()
```

### Content-Addressing
- Identity = SHA256 hash of serialized AST structure + inferred type
- Names are metadata, not identity — they map to hashes in the elaboration context
- Genesis builtins are seeded as pre-computed hashes, not special primitives

### Genesis Builtins
52 content-addressed modules (`m_*.erl`) implementing primitives. Each has a SHA256 hash. The first 10 bits are padded stubs. Everyone uses the same genesis block — no "builtin" identity system.

### Ability System
Handler stack on the process dictionary (`$ability_stack`):
- `Do(ability, operation, args)` -> `gleamunison_effets:do_op/4`
- `Handle(computation, handler, ability)` -> push handler, run computation, pop handler
- `validate_handler/3` checks completeness and arity at compile time
- `check_linearity/2` validates continuation variables are used exactly once

## Current Dogfood State

**Real levels**: 4235 across 82 dogfood files (v2-v83)
**Stub levels**: 0 (all gaps filled by auto-generated batches)
**Total levels**: 4235 (5320 including certs + meta runners)
**Unit tests**: 53
**Total verifications**: 4288
**Failures**: 0
**Generator**: `scripts/generate_levels.clj` — 21 template patterns cycled across 49 levels + 1 certification per batch
**Infinite loop**: `scripts/loop_infinite.clj` — fully autonomous; spawns `cmd` per batch, waits, repeats

### Level Distribution by Batch

| Batch | Levels | Coverage Area |
|---|---|---|
| 21-47 | Core | Term API, compile+load, effects, REPL, process dict |
| 48-55 | Benchmarks | Storage, DETS, serialization, large unit, dashboard |
| 1001-1048 | v2 | Guard clauses, use, holes, stdlib, HTTP client, JSON |
| 1049-1100 | v3 | HTTP edges, DateTime, filepath, crypto, concurrency |
| 1101-1150 | v4 | Pipeline, storage, sync, REPL, abilities, errors |
| 1151-1200 | v5 | Loader LRU, DETS lifecycle, jets, concurrency storms |
| 1201-1250 | v6 | Bracket edges, parser/lexer, hash identity, JSON deep |
| 1251-1300 | v7 | Phase 6 |
| 1301-1350 | v8 | Phase 7 |
| 1351-1400 | v9 | Phase 8 |
| 1401-1450 | v10 | Phase 9 |
| 1451-1500 | v11 | Phase 10 |
| 1501-1550 | v12 | Phase 11 |
| 1551-1600 | v13 | Phase 12 |
| 1601-1650 | v14 | Phase 13 |
| 1651-1700 | v15 | Crypto, json, metrics |
| 1701-1750 | v16 | HTTP server, health, effects stacking, datetime, template |
| 1751-1800 | v17 | Batch 17 |
| 1801-1900 | v18 | Batch 18 |
| 1901-2000 | v19 | Batch 19 |
| 2001-2100 | v20 | Batch 20 |
| 2101-2200 | v21 | Batch 21 |
| 2201-2270 | v22 | Jet fib, compile+load+eval roundtrip, cross-module chains |
| 2271-2320 | v23 | Handle compile, 7/7 pattern variants, guards, full pipeline |
| 2321-2370 | v24 | Cross-module RefTo exec, Handle full pipeline, REPL define+use |
| 2371-5320 | v25-v83 | Auto-generated (49 templates + 1 cert per batch, 21 patterns cycled) |

### Key Findings Documented During Dogfooding
| # | Finding | Level(s) |
|---|---------|----------|
| 1 | Erlang guards cannot reference pattern-bound variables | 2288 |
| 2 | Handle+Do handlers must be continuation-returning functions | 2322 |
| 3 | `eval_string` API does not bootstrap builtins or support `define` | 2311-2315 |
| 4 | Jet refs are genesis hash-locked — cannot dynamically register new jets | v22-v24 |
| 5 | HTTP server `start_server/1` enters blocking `server_control_loop` | v16 |
| 6 | `serialize_term`/`deserialize_term` work for string, int, list | v25+ |
| 7 | Generator template #21 (`gen-loader-limit`) never consumed — `(take 49)` drops it | v25+ |
| 8 | 1224 build warnings all unused imports/vars — cosmetic only | all batches |
| 9 | `cmd -p` requires `--yolo` for file write and shell permissions in auto loop | loop_infinite.clj |
| 10 | Prompt must be purely imperative — "analyze" triggers exploration deadlock | loop_infinite.clj |
