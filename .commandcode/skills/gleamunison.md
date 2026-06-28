---
name: gleamunison
description: Work with the gleamunison codebase — a content-addressed language runtime on the BEAM, built in Gleam. Use this skill when adding features, fixing bugs, writing dogfood levels, or understanding the architecture.
---

# Gleamunison Skill

## What is Gleamunison

gleamunison is a content-addressed language runtime with algebraic effects running on the Erlang BEAM, implemented in Gleam. It combines Unison-style content addressing (identity = SHA256 hash of AST + type), algebraic effects via process-dictionary handler stacks, and the BEAM as both target and constraint (hot code swapping, process isolation, OTP 29).

**Version**: 1.1.0
**Test suite**: 51 unit tests, 69 real dogfood levels (+979 stubs = 1050 total)

## Codebase Structure

```
src/
  gleamunison/           # 40 Gleam modules — core runtime + stdlib
    ast.gleam            # Core AST: Term (15 variants), Type, Definition, Unit
    identity.gleam       # Hash, DefinitionRef, LocalVar, genesis builtins
    codebase.gleam       # Content-addressed store, hash_of_definition
    compile.gleam        # AST → Erlang source → BEAM binary
    loader.gleam         # Dynamic module loading with LRU eviction
    inference.gleam      # Hindley-Milner type inference
    types.gleam          # TypeCache, InferenceError, validate_handler
    elaborate.gleam      # Surface → Core elaboration orchestration
    elab_term.gleam      # Term elaboration (15 surface variants → core)
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
  dogfood_v2.gleam       # v1.1.0 feature dogfood levels (1001-1048)
  gleamunison.gleam      # Main entry point (CLI dispatch)
  gleamunison_*.erl      # 20+ Erlang FFI modules
  m_*.erl                # 52 genesis modules (content-addressed builtins)

test/                    # Gleam test files
  gleamunison_test.gleam # Main test suite (51 tests)
  *.gleam                # Additional test files

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
  adr/                   # 48 Architecture Decision Records
  playbook/              # 11 playbook files (levels 0001-1050)
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
Content-addressed modules use the `m_` prefix followed by the last 8 hex characters of the hash (e.g., `m_e8e52932`). This prevents collisions with any Gleam module (Gleam modules use lowercase letters and single `_` separators).

## Common Gotchas

### `bit_array.to_string/1` returns `Result`, not `String`
```gleam
// WRONG:
let s = bit_array.to_string(b)
io.println("Value: " <> s) // Type error: expected String, got Result(String, Nil)

// CORRECT:
let s = case bit_array.to_string(b) { Ok(s) -> s; _ -> "" }
// Or use a local unpack helper:
fn unpack(b: BitArray) -> String {
  case bit_array.to_string(b) { Ok(s) -> s; _ -> "" }
}
```

### Erlang BIF name conflicts
Avoid naming module exports after Erlang BIFs: `apply/2`, `spawn/1`, `list_to_binary/1` shadow custom functions. Use alternatives: `adapt/2`, `start_task/1`, `to_bin/1`.

### Gleam case branches — no semicolons
Gleam v1.0+ removed semicolons. Case branches use only newlines:
```gleam
// WRONG:
case x { Ok(s) -> s; Error(_) -> "" }

// CORRECT:
case x { Ok(s) -> s _ -> "" }
```

### Labeled constructor pattern matching
Custom types with labeled fields cannot be partially matched. Use wildcard `..` then destructure:
```gleam
// WRONG:
ast.Lambda(binder: _, body) -> ... // "unexpected positional argument after labeled argument"

// CORRECT:
ast.Lambda(..) -> {
  let ast.Lambda(binder: _, body: b) = term
  ...
}
```

### Opaque type field access
`pub opaque type` prevents field access from outside the defining module. Use accessor functions instead:
```gleam
// WRONG:
let ts = dt.timestamp // "field does not exist"

// CORRECT:
let iso = datetime.to_iso8601(dt) // Use public API
```

### Erlang charlist vs binary
Many Erlang stdlib functions return charlists (string lists), not binaries. Wrap with `list_to_binary/1`:
```erlang
% WRONG:
calendar:system_time_to_rfc3339(...) % Returns charlist, Gleam sees List(Int)

% CORRECT:
list_to_binary(calendar:system_time_to_rfc3339(...)) % Returns UTF-8 binary
```

### ETS ordered_set requires tuple keys
`ordered_set` tables require tuple keys. A bare integer causes a `badarg` crash:
```erlang
% WRONG:
ets:new(table, [ordered_set, named_table]),
ets:insert(table, 0).

% CORRECT:
ets:new(table, [ordered_set, named_table]),
ets:insert(table, {erlang:unique_integer()}).
```

## Dogfooding

### How Levels Work
Each dogfood level is a public function `pub fn levelN() -> Nil` that exercises a specific runtime capability. Levels are organized by feature domain:

| Range | Domain | File |
|---|---|---|
| 21–47 | Core runtime (Term API, compile, effects, REPL) | `dogfood_core.gleam` |
| 48–55 | Benchmarks (storage, DETS, serialization, large units) | `dogfood_bench.gleam` |
| 70 | Meta-runner | `dogfood_meta.gleam` |
| 1001–1048 | v1.1.0 features (guards, use, holes, stdlib, ops) | `dogfood_v2.gleam` |
| All others | Stubs | Generated by `dogfood.gleam` |

### Adding a New Level
1. Write the level function in the appropriate file (or create a new `dogfood_v3.gleam` for the next batch)
2. Register it in `dogfood_meta.gleam` → `real_levels_list()`
3. Ensure the range in `dogfood.gleam` → `all_levels()` covers the new level number
4. Write the playbook entry in `docs/playbook/` with goal, expected results, and location
5. Test: `gleam run -- levelN`

### Running Levels
```sh
gleam run -- level1001    # Run a single level
gleam run -- all           # Run all 1-1050 (real + stubs)
gleam test                 # Run unit test suite
```

## Testing
- `gleam test` — runs 51 unit tests covering hashing, storage, parser, loader, effects, sync, elaboration, inference
- `gleam run -- levelN` — runs a specific dogfood level
- Each level prints `--- Level N: Description ---` header and `Level N: OK` on success
- Failed assertions produce `let assert` runtime errors with unmatched value
- For the `-- all` command, real levels run first, stubs print `[stub]` messages

## Common Operations

### Adding a New Gleam Module
1. Create `src/gleamunison/new_module.gleam` under 250 LOC
2. If it needs Erlang FFI, create `src/gleamunison_new_module.erl`
3. Add the Erlang module to the escript build script if it produces BEAM files
4. Add module to README.md module table
5. Build: `gleam build`
6. Test: add dogfood levels OR unit tests

### Adding a New AST Variant
1. Add variant to `ast.gleam` → `pub type Term { ... }`
2. Add hashing case in `codebase.gleam` → `fn hash_term(term)`
3. Add compilation case in `compile.gleam` → `fn emit_term(t)`
4. Add inference case in `inference.gleam` → `fn infer_term(term, cache)`
5. Add surface type in `elab_types.gleam` → `pub type SurfaceTerm`
6. Add elaboration in `elab_term.gleam` → `fn elaborate_term(term, ctx)`
7. Add parser support in `parser.gleam` → `fn sexpr_to_term(sexpr)`
8. Update all existing `Case` constructors to include the new `guard` field if needed
9. Update tests that construct the affected AST nodes

### Adding a New Feature to the REPL
1. Add surface syntax parsing in `parser.gleam`
2. Add elaboration in `elab_term.gleam`
3. Add compilation in `compile.gleam`
4. Add dogfood levels exercising the new feature
5. Update `repl.gleam` if new builtins are needed at REPL bootstrap

## Key Architectural Notes

### The Pipeline
```
S-expression text → Parser → SurfaceTerm → Elaborator → Core AST + Type
    → Hasher (SHA256) → DefinitionRef
    → Compiler (Erlang source → BEAM binary)
    → Loader (code:load_binary/3)
    → $eval()
```

### Content-Addressing
- Identity = SHA256 hash of serialized AST structure + inferred type
- Names are metadata, not identity — they map to hashes in the elaboration context
- Genesis builtins are seeded as pre-computed hashes, not special primitives

### Genesis Builtins
52 content-addressed modules (`m_*.erl`) implementing primitives. Each has a SHA256 hash. The first 10 bits are padded stubs. Everyone uses the same genesis block — no "builtin" identity system.

### Ability System
Handler stack on the process dictionary (`$ability_stack`):
- `Do(ability, operation, args)` → `gleamunison_effets:do_op/4`
- `Handle(computation, handler, ability)` → push handler, run computation, pop handler
- `validate_handler/3` checks completeness and arity at compile time
- `check_linearity/2` validates continuation variables are used exactly once

## Current Dogfood State (Post-Levels-1250)

**Real levels**: 271 (21 core/bench + 48 v2 + 52 v3 + 50 v4 + 50 v5 + 50 v6)
**Stub levels**: 979
**Next batch**: Levels 1251–1300 — macros, package registry, LSP protocol handlers, distributed tracing, gleam format

## Progress Tracking

### Implemented in this session
- [x] 48 dogfood levels (1001–1048) — guard clauses, use, holes, linearity, JSON, DateTime, filepath, crypto, template, logging, config, health, metrics, property testing, trace, CAS adapters, integration
- [x] 52 dogfood levels (1049–1100) — HTTP client, JSON edges, DateTime parse/format, filepath edges, crypto algos, concurrent access, error edges, performance, integration
- [x] Fixed datetime FFI — charlist → binary
- [x] Fixed template binary key lookup
- [x] Fixed metrics telemetry crash
- [x] Fixed ETS ordered_set insertion in log
- [x] Fixed crypto string_to_algo — binary pattern matching
- [x] Fixed JSON decode — catch exceptions from json:decode

- [x] 50 dogfood levels (1101–1150) — pipeline, storage, sync, REPL, abilities, errors, concurrency, dashboard, performance, integration
- [x] 50 dogfood levels (1151–1200) — loader LRU, DETS lifecycle, jets, sync+storage, concurrency storms, error stress, effect chains, distributed, integration
- [x] 50 dogfood levels (1201–1250) — bracket edges, parser/lexer edges, hash identity, JSON edges, crypto edges, datetime+filepath, operations deeper
- [x] 271 total real dogfood levels (21 + 48 + 52 + 50 + 50 + 50)
- [x] 51 unit tests pass

### Next 50 Levels (1251–1300)
| Range | Domain | Levels | Status |
|---|---|---|---|
| 1251–1256 | Macros + metaprogramming | 6 | PENDING |
| 1257–1262 | Package registry | 6 | PENDING |
| 1263–1268 | LSP protocol handlers | 6 | PENDING |
| 1269–1274 | Distributed tracing | 6 | PENDING |
| 1275–1280 | Gleam format + tooling | 6 | PENDING |
| 1281–1286 | Production deployment | 6 | PENDING |
| 1287–1292 | Security hardening | 6 | PENDING |
| 1293–1298 | Documentation gen + API | 6 | PENDING |
| 1299–1300 | Full release certification | 2 | PENDING |
