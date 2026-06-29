# Dogfooding Playbook — Levels 1601–1650

Tests covering guard error fix verification, ability dispatch through stacked handlers, pattern elaboration depth, compile deep edges (nested Let+Match, closure-of-closure, PatConstructor guard), lexer multi-line strings, property test failure path, complex REPL expressions, Mnesia bulk insert, typecheck with ability references, jet miss verification, HTTP deeper routes, storage 3000-insert stress, and cross-module integration.

All levels are real implementations in `src/dogfood_v14.gleam`.

---

## Level 1601–1603: Guard Error Fix Verification

**Level 1601** — Parse+Elaborate match with valid guard: `(match 42 (x ? 1 x))`.
- **Expected:** Guard elaborates correctly.

**Level 1602** — Elaborate match with undefined variable in guard.
- **Expected:** Error propagates (previously swallowed to `Int(0)` due to `result.unwrap`).

**Level 1603** — End-to-end `elaborate_unit` with valid guard.
- **Expected:** Unit elaborated successfully.

---

## Level 1604–1606: Ability Dispatch Through Stacked Handlers

**Level 1604** — Dual handler chain: State + IO abilities.
- **Expected:** Both handlers installed, `effects_run` completes without crash.

**Level 1605** — 4 distinct ability keys (State, IO, Timer, Process).
- **Expected:** All 4 keys are different (deduped list length = 4).

**Level 1606** — Duplicated same handler frame in chain.
- **Expected:** `effects_run` handles duplicate handler IDs gracefully.

---

## Level 1607–1609: Pattern Elaboration Depth

**Level 1607** — Elaborate `SPCons("h", "t")` → `PatCons`.
- **Expected:** Produces correct PatCons AST node.

**Level 1608** — Parse nested constructor pattern: `(match (pair (pair 1 2) 3) ((pair (pair a b) c) ...))`.
- **Expected:** Parsed as SMatch with SPConstructor in case pattern.

**Level 1609** — Elaborate `SPAs("xs", SPCons("h", "t"))` → `PatAs + PatCons`.
- **Expected:** Produces `PatAs(Local(n), PatCons(Local(n+1), Local(n+2)))`.

---

## Level 1610–1612: Compile Deep Edges

**Level 1610** — Compile deeply nested Let+Match with guards.
- **Expected:** Produces BEAM bytes.

**Level 1611** — Compile closure-of-closure: `(lam f (f (lam x (f x))))`.
- **Expected:** Produces BEAM bytes.

**Level 1612** — Compile match with `PatConstructor` + guard.
- **Expected:** Produces BEAM bytes with Erlang `when` clause.

---

## Level 1613–1614: Lexer Multi-line

**Level 1613** — Tokenize string with actual newline character `\n`.
- **Expected:** Produces at least 1 token (not unterminated).

**Level 1614** — Tokenize string with escaped newline `\\n` (multi-line).
- **Expected:** Produces at least 1 token.

---

## Level 1615–1617: Property Test Failing Path

**Level 1615** — Property: gen returns -1, prop checks `x > 0`.
- **Expected:** Returns error result (property fails).

**Level 1616** — Property: gen returns 7, prop checks `x > 0`.
- **Expected:** Returns `Ok`.

**Level 1617** — Property: gen returns 1, prop checks `x == 1`.
- **Expected:** Returns `Ok`.

---

## Level 1618–1621: Complex REPL

**Level 1618** — `((lam a (lam b (lam c (add a (add b c))))) 1 2 3)` via eval.
- **Expected:** Returns `"6"`.

**Level 1619** — Filter+mapped list operations chain.
- **Expected:** Returns correct filter count.

**Level 1620** — `((lam a (lam b (add a b)) 7) 3)` closure application.
- **Expected:** Returns `"10"`.

**Level 1621** — `(fact 7)` recursive factorial.
- **Expected:** Returns `"5040"`.

---

## Level 1622–1626: Storage + Typecheck + Jet Edges

**Level 1622** — Mnesia bulk: insert 100 refs, verify `list_refs`.
- **Expected:** Returns 100 refs.

**Level 1623** — Typecheck `Handle` with ability reference in cache.
- **Expected:** Typecheck passes or errors appropriately.

**Level 1624** — `infer_term` for `Do` with ability in type cache.
- **Expected:** Returns inferred type from operation output.

**Level 1625** — `get_jet` on random hash (miss).
- **Expected:** Returns `None`.

**Level 1626** — Typecheck cross-def with AbilityDecl + TermDef referencing it.
- **Expected:** Typecheck processes both defs.

---

## Level 1627–1631: HTTP Deeper

**Level 1627** — GET / and /index.html static serve.
- **Expected:** Both return HTTP responses.

**Level 1628** — Define + browse workflow via HTTP.
- **Expected:** Defined function appears in browse list.

**Level 1629** — GET /eval?expr=(mul 3 5) via HTTP.
- **Expected:** Returns `{"result":"15"}`.

**Level 1630** — Define 3 vars via HTTP then browse.
- **Expected:** All 3 appears in browse.

**Level 1631** — /api/status + /api/health combination.
- **Expected:** Both return valid JSON.

---

## Level 1632–1635: Complex Eval Chains

**Level 1632** — HOF chain: `((lam f (lam g (f (g 6)))) inc (mul 3))`.
- **Expected:** Returns result.

**Level 1633** — String operations in nested let.
- **Expected:** Returns correct string length.

**Level 1634** — Match with string pattern.
- **Expected:** `"abc"` matches `"abc"` case.

**Level 1635** — List fold with multiplication: `(list-fold mul 1 (list 2 3 4))`.
- **Expected:** Returns `"24"`.

---

## Level 1636–1640: Storage + Codebase Stress

**Level 1636** — In-memory storage: 3000 inserts.
- **Expected:** All 3000 succeed.

**Level 1637** — Codebase insert → adapter lookup roundtrip.
- **Expected:** Data survives roundtrip.

**Level 1638** — REPL define 3 vars via `handle_define`.
- **Expected:** All 3 defines succeed.

**Level 1639** — Compile AbilityDecl with 3 multi-input ops.
- **Expected:** Produces BEAM bytes.

**Level 1640** — Mixed unit insert (TermDef + TypeDef + TermDef), verify `list_refs`.
- **Expected:** 3 refs returned.

---

## Level 1641–1650: Integration Certification

**Level 1641** — Full builtin chain: `add(string-length("hello"), list-length(filter(even?(mod 2), range 1 10)))`.
- **Expected:** Returns correct result.

**Level 1642** — Compile → Load → Eval roundtrip (identity lambda).
- **Expected:** Returns eval result.

**Level 1643** — Log + Counter + Trace + JSON cross.
- **Expected:** All 4 modules exercise.

**Level 1644** — Typecheck + Loader + Codebase cross.
- **Expected:** All 3 modules exercise.

**Level 1645** — Effects + Lexer + Parser cross.
- **Expected:** All 3 modules exercise.

**Level 1646** — Eval conditional: absolute value `(abs -7)`.
- **Expected:** Returns `"7"`.

**Level 1647** — String operations bulk: `string-length(string-replace(string-upcase(...)))`.
- **Expected:** Returns correct result.

**Level 1648** — List transform: `list-fold sum of squares of range 1-5`.
- **Expected:** Returns `"55"`.

**Level 1649** — Batch 14 summary.
**Level 1650** — v2.6 full certification: 671 dogfood + 52 unit = 723 total verifications.
