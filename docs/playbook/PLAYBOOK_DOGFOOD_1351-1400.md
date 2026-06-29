# Dogfooding Playbook — Levels 1351–1400

Tests covering TCP sync protocol deep (pull/push with data and error paths),
compile all 15 AST variants, inference helper functions (substitute, list_all_match),
loader edge cases (CompileFailed caching, multi-eviction LRU, known-loaded idempotent, limit 1),
ability definition elaboration, effects multi-op handler dispatch, jet bypass verification,
REPL define+eval roundtrip, property checking, parser pattern forms, elaboration context,
codebase HashMismatch error, and cross-module integration.

All levels are real implementations in `src/dogfood_v9.gleam`.

---

## Level 1351–1355: TCP Sync Deep

**Level 1351** — Pull sync with data: start TCP server, insert def, pull from client.
- **Expected:** Sync returns list of new refs (may be 0 if server has no data).

**Level 1352** — Pull sync to unreachable peer `"dead-host:63999"`.
- **Expected:** Returns `Error(ConnectionFailed(_, PeerNotFound(_)))`.

**Level 1353** — Push sync with adapter data: insert ref in inmemory storage, push it.
- **Expected:** Push returns ref count (may be 1 if server reaches, or error if unreachable).

**Level 1354** — Push sync empty refs list.
- **Expected:** Returns `Ok(#(_, 0))`.

**Level 1355** — Push sync to unreachable peer.
- **Expected:** Returns `Error(ConnectionFailed(_))`.

---

## Level 1356–1363: Compile All AST Variants

**Level 1356** — Compile `Float(3.14)` + `Text(<<"hi">>)`.
- **Expected:** Both produce non-zero BEAM bytes.

**Level 1357** — Compile `Let(0, Int(1), LocalVarRef(0))`.
- **Expected:** Produces BEAM bytes.

**Level 1358** — Compile `Match(Int(1), [Case(PatInt(1), None, Int(42)), Case(PatInt(2), None, Int(99))])`.
- **Expected:** Produces BEAM bytes.

**Level 1359** — Compile `List([Int(1), Int(2), Int(3)])`.
- **Expected:** Produces BEAM bytes.

**Level 1360** — Compile `Construct(builtin_pair(), [Int(1), Int(2)])`.
- **Expected:** Produces BEAM bytes.

**Level 1361** — Compile `Use(binder, RefTo(add), LocalVarRef)`.
- **Expected:** Use sugar desugars and compiles correctly.

**Level 1362** — Compile match with guard: `Case(PatInt(1), Some(GuardTerm(Int(99))), body)`.
- **Expected:** Guard emits Erlang `when` clause, produces BEAM bytes.

**Level 1363** — Compile `List([RefTo(add), RefTo(sub)])`.
- **Expected:** List of refs compiles correctly.

---

## Level 1364–1367: Inference Helpers

**Level 1364** — `substitute(TypeVar(0), 0, Int) → Int`.
- **Expected:** Returns `Builtin(IntType)`.

**Level 1365** — `substitute(TypeVar(1), 0, Int) → TypeVar(1)`.
- **Expected:** Non-matching variable unchanged.

**Level 1366** — `substitute(Fn([TypeVar(0)], TypeVar(0), ...), 0, Int)`.
- **Expected:** Both param and result replaced with Int.

**Level 1367** — `list_all_match([], t, cache, infer_term)`.
- **Expected:** Returns `True`.

---

## Level 1368–1371: Loader Deeper

**Level 1368** — `ensure_loaded` with Hole (expected: runtime error compilation), retry returns cached error.
- **Expected:** Second call returns cached `CompileFailed` or `LoadFailed`.

**Level 1369** — LRU with limit 3, loading 6 defs: oldest 3 should be evicted.
- **Expected:** `is_loaded` returns False for r1-r3, True for r4-r6.

**Level 1370** — `ensure_loaded` on already-loaded ref: idempotent, returns Ok.
- **Expected:** `is_loaded` True both before and after re-load.

**Level 1371** — `new_loader_with_limit(1)`: load def1, load def2, r1 evicted.
- **Expected:** `is_loaded(r1)` = False, `is_loaded(r2)` = True.

---

## Level 1372–1374: AbilityDef Elaboration

**Level 1372** — `elab_ability_def` with 2 operations (print + log), both Text→Int.
- **Expected:** Produces `AbilityDecl` with correct Operation nodes.

**Level 1373** — `elaborate_unit` with TermDef + TypeDef + AbilityDef mixed.
- **Expected:** All 3 definitions elaborated, 3 defs in ast.Unit.

**Level 1374** — `elaborate_unit` with two abilities (Console + Logger) + term.
- **Expected:** Ctx has both ability names in `abilities` dict, ops registered with indices.

---

## Level 1375–1377: Effects Multi-Op

**Level 1375** — Compute ability_key suffix from `builtin_state_get` hash.
- **Expected:** Produces 8-char hex suffix in format `"m_XXXXXXXX"`.

**Level 1376** — HandlerFrame with 2 ops (indices 0 and 1).
- **Expected:** `effects_run` returns `Dynamic(42)` through default thunk.

**Level 1377** — Nested abilities: State inside IO, each with handler.
- **Expected:** Both `effects_run` calls succeed, inner returns 777, outer returns 888.

---

## Level 1378–1380: Jet + REPL + Property

**Level 1378** — `get_jet` with fib hash (123 in 256-bit).
- **Expected:** Returns `Some(body)` where body contains `"fib"`.

**Level 1379** — `handle_define("x", 42)` → verify define succeeds.
- **Expected:** Returns `Ok(#(cache, defs))` with updated cache.

**Level 1380** — `ffi_prop` with trivial property (gen:1, prop: x==1).
- **Expected:** Returns `Ok` result.

---

## Level 1381–1384: Parser Pattern Forms

**Level 1381** — Parse `(match (Cons 1 Empty) ((Cons h t) body))`.
- **Expected:** Constructor pattern parsed as `SPConstructor` in case.

**Level 1382** — Parse `(fn* ((x 10) (y 20)) (add x y))`.
- **Expected:** Parsed as `SLabeledFn` with two defaults.

**Level 1383** — Parse `(type MyType (MyCtor Int))`.
- **Expected:** Returns `SList` with `"type"`, `"MyType"`, and ctor terms.

**Level 1384** — Parse `((((((((((((42))))))))))))` (12-level nesting).
- **Expected:** Parses successfully.

---

## Level 1385–1387: Elaboration Context

**Level 1385** — `add_binding("a")` → `lookup_binding("a")`.
- **Expected:** Returns same `LocalVar` from lookup that `add_binding` produced.

**Level 1386** — `elaborate_pattern(SPConstructor("MyCtor", [SPInt(1), SPVar("x")]))`.
- **Expected:** Produces `PatConstructor(ref, [PatInt(1), PatVar(lv)])`.

**Level 1387** — Chain: `elaborate_pattern(As("xs", Cons("h", "t")))` → `elaborate_pattern(EmptyList)`.
- **Expected:** Both patterns elaborate correctly in sequence.

---

## Level 1388–1390: Codebase Deeper

**Level 1388** — `insert` with unit root hash ≠ definition hash.
- **Expected:** Returns `Error(HashMismatch(expected, got))`.

**Level 1389** — Hash all 15 AST variants.
- **Expected:** 15 hashes computed without crash.

**Level 1390** — Insert → get_adapter → lookup: bytes persist correctly.
- **Expected:** Lookup returns `Some(bytes)` with non-zero byte_size.

---

## Level 1391–1400: Integration Certification

**Level 1391** — HTTP (JSON) + Storage + Crypto + Counter + Histogram.
- **Expected:** All 5 modules exercise without crash.

**Level 1392** — Loader + Compile + Codebase: insert def, ensure_loaded, verify is_loaded.
- **Expected:** `is_loaded` returns True after successful load.

**Level 1393** — Sync + Storage: push def over TCP, verify count or error handled.
- **Expected:** No crash.

**Level 1394** — Datetime + Filepath + Log: ISO timestamp, root path construction, info log.
- **Expected:** All 3 modules exercise without crash.

**Level 1395** — Trace + Counter + Log: capture 2 traces, counter increment, info log.
- **Expected:** Traces list returned, counter set, log written.

**Level 1396** — Parse → Elaborate → Infer: `(let x 42 (lam y (add x y)))` through full pipeline.
- **Expected:** Inferred type printed.

**Level 1397** — Effects + Jet + Loader: empty effects run, jet lookup, identity lambda load.
- **Expected:** All 3 modules exercise without crash.

**Level 1398** — Tokenize + Hash + Typecheck: tokenize input, hash definition, infer type.
- **Expected:** Token count, hash prefix, and inferred type printed.

**Level 1399** — Batch 9 summary.
- **Expected:** Prints 50-level summary.

**Level 1400** — v2.1 full certification: 421 total real dogfood levels, 51 unit tests, 472 total conformance verifications across 11 playbook files.
- **Expected:** Prints final certification banner.
