# Dogfooding Playbook — Levels 1401–1450

Tests covering HTTP route coverage (12 endpoint routes), normalize_type / substitute deeper
(AbilityVar identity, nested Fn, App substitution), REPL error codes (E002–E005, redefine),
lexer edges (empty string, comment, unicode), parser edges (SPText pattern, Cons pattern,
deep nesting >100, define as SList), codebase/storage stress (200 defs, DETS reopen,
500-insert), SConstruct elaboration, binding shadow, multi-input ability ops, SRef,
compile edges (empty list, nested Let, TypeDef, empty Match), inference deeper
(list_all_match heterogeneous, check_linearity, Do op bounds), sync multi-ref,
jet miss, property check, full pipeline roundtrip, loader soft purge,
and cross-module integration.

All levels are real implementations in `src/dogfood_v10.gleam`.

---

## Level 1401–1412: HTTP Route Coverage

**Level 1401** — GET /counter on running server.
- **Expected:** HTTP response (JSON with count).

**Level 1402** — GET /browse on running server.
- **Expected:** HTTP response (JSON with defs list).

**Level 1403** — GET /api/processes on running server.
- **Expected:** HTTP response (JSON with process list).

**Level 1404** — GET /api/sync-status on running server.
- **Expected:** HTTP response (JSON with genesis_count, modules).

**Level 1405** — GET /api/modules on running server.
- **Expected:** HTTP response (JSON with modules list).

**Level 1406** — GET /api/logs on running server (after log entry).
- **Expected:** HTTP response (JSON with log entries).

**Level 1407** — GET /api/traces on running server (after trace capture).
- **Expected:** HTTP response (JSON with traces list).

**Level 1408** — GET /api/traces/:id on running server (after trace capture).
- **Expected:** HTTP response (trace detail or 404).

**Level 1409** — GET /api/redefinitions on running server.
- **Expected:** HTTP response (JSON with events).

**Level 1410** — GET / (root route) on running server.
- **Expected:** HTTP 200 response (serves static content).

**Level 1411** — GET with path traversal (`../`, `../../../etc/passwd`).
- **Expected:** HTTP 403 or safe response.

**Level 1412** — GET nonexistent route → 404.
- **Expected:** HTTP response (404 or server default).

---

## Level 1413–1415: Normalize Type + Substitute

**Level 1413** — `normalize_type(AbilityVar(0))` and `AbilityVar(7)`.
- **Expected:** Both return themselves unchanged (identity).

**Level 1414** — `normalize_type(Fn([Fn([TypeVar(0)], TypeVar(0))], TypeVar(0), ...))`.
- **Expected:** Inner and outer TypeVar(0) independently reindexed.

**Level 1415** — `substitute(App(ref, [TypeVar(0), TypeVar(1)]), 0, Int)`.
- **Expected:** Only TypeVar(0) replaced; TypeVar(1) unchanged.

---

## Level 1416–1420: REPL Error Codes

**Level 1416** — E002: `do_eval(SDo("Console", "nonexistent", ...))`.
- **Expected:** Returns `Error` containing `"E002"`.

**Level 1417** — E003: `do_eval(SHandle(42, 99, "NoSuch"))`.
- **Expected:** Returns `Error` containing `"E003"`.

**Level 1418** — E001/E004: `do_eval(SApply(SVar("undefined_x"), SInt(1)))`.
- **Expected:** Returns `Error` with E001 (name not found) or E004 (inference error).

**Level 1419** — E005: `do_eval(SGuardGuard(SInt(1)))`.
- **Expected:** Returns `Error` containing `"E005"`.

**Level 1420** — `handle_define("v", 1)` then `handle_define("v", 99)`.
- **Expected:** Second define succeeds; old definition filtered out (shadowing).

---

## Level 1421–1423: Lexer Edges

**Level 1421** — Tokenize empty string `""""`.
- **Expected:** At least 1 token produced.

**Level 1422** — Tokenize `"42 ; this is a comment"`.
- **Expected:** Exactly 1 token (comment consumed).

**Level 1423** — Tokenize unicode identifier `"λ"`.
- **Expected:** At least 1 token produced.

---

## Level 1424–1427: Parser Edges

**Level 1424** — Parse `(match "hello" ("hello" 1) (_ 0))`.
- **Expected:** SPText pattern correctly parsed in match case.

**Level 1425** — Parse `(match xs ((Cons h t) h))`.
- **Expected:** Cons constructor pattern correctly parsed.

**Level 1426** — Parse deeply nested expression (150 levels).
- **Expected:** Parses successfully without stack overflow.

**Level 1427** — Parse `(define foo 42)` and verify SList result.
- **Expected:** Returns `SList([SVar("define"), SVar("foo"), SInt(42)])`.

---

## Level 1428–1430: Codebase + Storage Stress

**Level 1428** — Insert 200 definitions into codebase, verify list_refs count.
- **Expected:** 200+ refs returned.

**Level 1429** — DETS reopen persistence: create → insert → close → reopen → lookup.
- **Expected:** Data survives close/reopen cycle.

**Level 1430** — In-memory storage: insert 500 values.
- **Expected:** All inserts succeed without error.

---

## Level 1431–1434: Elaboration + Context

**Level 1431** — `elaborate_term(SConstruct("Pair", [SInt(1), SInt(2)]), ctx)`.
- **Expected:** Produces `Construct(pair_ref, [Int(1), Int(2)])`.

**Level 1432** — `add_binding("x")` twice (shadowing).
- **Expected:** Second binding gets different LocalVar; lookup returns last binding.

**Level 1433** — `elab_ability_def` with multi-input op (Text + Int → Float).
- **Expected:** Produces AbilityDecl with correct multi-input Operation.

**Level 1434** — `elaborate_term(SRef(add_ref), ctx)`.
- **Expected:** Produces `RefTo(add_ref)`.

---

## Level 1435–1438: Compile Edges

**Level 1435** — Compile `List([])` (empty list).
- **Expected:** Produces BEAM bytes.

**Level 1436** — Compile deeply nested Let (3 levels).
- **Expected:** Produces BEAM bytes with correct Erlang variable scoping.

**Level 1437** — Compile `TypeDef(Structural(...))`.
- **Expected:** Produces BEAM bytes (compiles to "ok").

**Level 1438** — Compile `Match(Int(1), [])` (empty cases).
- **Expected:** Produces BEAM bytes (degenerate case clause).

---

## Level 1439–1441: Inference Deeper

**Level 1439** — `list_all_match` with heterogeneous elements `[Int(1), Float(2.0)]`.
- **Expected:** Returns `False`.

**Level 1440** — `check_linearity` on `Let(0, Int(42), LocalVarRef(0))`.
- **Expected:** Returns `Ok(Nil)`.

**Level 1441** — `infer_term` on `Do(ability, Local(0), [])` with valid op index.
- **Expected:** Returns `Ok(Type)`.

---

## Level 1442–1444: Sync + Jet + Property

**Level 1442** — Pull sync with 2 definitions in codebase.
- **Expected:** Returns refs list (may be 0–2 depending on server state).

**Level 1443** — `get_jet` on random (non-jet) hash.
- **Expected:** Returns `None`.

**Level 1444** — Property check with `fn() { 42 }` and `x == 42`.
- **Expected:** Returns `Ok` result.

---

## Level 1445–1450: Integration Certification

**Level 1445** — Full pipeline: parse → elaborate → compile → load + eval.
- **Expected:** `(let f (lam x (add x 1)) (f 41))` runs through all stages.

**Level 1446** — Loader soft purge: limit=2, load 3 defs, evict oldest.
- **Expected:** r1 evicted, r2 and r3 loaded.

**Level 1447** — 7-module cross: Health + Counter + Trace + Log + JSON + Crypto + DateTime.
- **Expected:** All modules exercise without crash.

**Level 1448** — Sync + Lex + Parser + Typecheck cross.
- **Expected:** All 4 modules exercise without crash.

**Level 1449** — Batch 10 summary.
- **Expected:** Prints 50-level summary.

**Level 1450** — v2.2 full certification: 471 total real dogfood levels, 51 unit tests, 522 total conformance verifications across 12 playbook files.
- **Expected:** Prints final certification banner.
