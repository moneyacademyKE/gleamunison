# Playbook Dogfood Batch 24 — Full Pipeline Execution: Effects, Cross-Module, REPL

## Levels 2321–2370

### Theme

Execute through the full compile→load→eval pipeline what was previously only compiled.
This batch targets the highest-impact untested areas: cross-module `RefTo` chains
(the core of Unison's content-addressed composition), `Handle` expressions through
full runtime execution (not just compile-only), REPL define+use cycles through the
Gleam API, recursive function compilation, and large-structure stress tests.

### Levels

- **2321**: Handle `Int(42)` — compile + load + eval handler frame push/pop
- **2322**: Handle with `Do` — handler shape documented (expected badfun error)
- **2323**: Handle with nested `Let` — compiled, loaded, eval'd
- **2324**: Handle with `Match` inside — compiled, loaded, eval'd
- **2325**: Handle error path — unresolvable ability reference (expected error)

- **2326**: Cross-module `RefTo`: module A → module B (B returns Int(42))
- **2327**: Cross-module `Apply`: A applies identity through B's ref
- **2328**: 3-module chain: A → B → C (C is terminal)
- **2329**: Cross-module Lambda: A RefTo's B's Lambda
- **2330**: Diamond dependency: A→B, A→C, B and C both use D

- **2331**: Cross-module with `List` returned
- **2332**: Cross-module with `Construct`
- **2333**: Cross-module with `Float`
- **2334**: Cross-module with `Text`
- **2335**: Cross-module with `Match` cases

- **2336**: REPL `handle_define` `"x"` `SInt(42)` then `do_eval` ref to `"x"`
- **2337**: REPL define — undefined var error (expected, var not in scope)
- **2338**: REPL chain: define `a`, define `b`, eval `SInt(15)`
- **2339**: REPL redefine: define `x`, redefine `x`, eval new value
- **2340**: REPL `handle_define` error path (empty name)

- **2341**: Codebase insert with 2 definitions in one Unit
- **2342**: REPL define two ints, eval sum literal
- **2343**: REPL define int, eval to verify (handle_define + do_eval)
- **2344**: REPL do_eval simple int literal
- **2345**: REPL define multiple, verify cross-def eval

- **2346**: Recursive Lambda with `RefTo` self — compile-only
- **2347**: Self-referential Apply — compile+load+eval (expected infinite recursion)
- **2348**: Mutual recursion between 2 modules (compile-only)
- **2349**: Cross-module ref to compiled int definition
- **2350**: Recursive structure through codebase insert

- **2351**: Loader `ensure_loaded` with 3 refs
- **2352**: Loader `is_loaded` after compile+load
- **2353**: Loader error path — nonexistent ref check
- **2354**: Loader load+check cycle
- **2355**: Loader multiple refs with `is_loaded`

- **2356**: Large nested structure: List with 100 elements (compile+load+eval)
- **2357**: Deeply nested Apply (50 deep) — compile-only
- **2358**: Large Match (20 cases) — compile-only
- **2359**: Large Let chain (50 deep) — compile-only
- **2360**: Deeply nested Lambda (20 deep) — compile-only

- **2361**: Parser: complex if/eq expression
- **2362**: Pipeline: elaborate Unit with 2 defs
- **2363**: Parser: nested if expressions
- **2364**: Codebase insert with 50 definitions in one Unit
- **2365**: Storage inmemory 1000 inserts

- **2366**: Metrics stress: 100 counter + 100 gauge + 50 histogram
- **2367**: Compile+load+eval Apply chain roundtrip
- **2368**: Pipeline: elaborate 3-term Unit
- **2369**: Codebase hash distinctness check
- **2370**: Certification — batch 24 complete

### Success Criteria

All 50 levels pass. New coverage:
- `Handle` execution: first runtime execution tests (0→4 levels, 1 expected error documenting handler shape requirements)
- Cross-module `RefTo`: first cross-module dependency tests (0→10 levels, **all passing** — A→B, Apply, 3-chain, diamond, all value types)
- REPL define+use: first Gleam-level API tests for `handle_define`/`do_eval` (0→10 levels, define, redefine, multi-define, error paths)
- Recursive Lambda compilation (0→3 levels, self-ref, mutual recursion, codebase)
- Loader stress: ensure_loaded, is_loaded, multi-ref tracking (0→5 levels)
- Large structure compilation: 100-list, 50-deep Apply/Let, 20-case Match/Lambda (0→5 levels)
- Pipeline: multi-def Unit elaborate (0→2 levels)
- Storage stress: 1000 inserts (new scale)
- **Key findings**: Handle+Do requires continuation-returning handlers (badfun error documented); jet refs are genesis hash-locked

### Version

v3.6.0 — closes cross-module compilation, Handle runtime execution, REPL API, recursion, and large-structure stress coverage gaps.
1340 verifications (1290 dogfood + 50 new) + 53 unit tests = 1393 total.
