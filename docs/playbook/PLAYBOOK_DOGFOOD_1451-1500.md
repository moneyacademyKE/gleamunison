# Dogfooding Playbook — Levels 1451–1500

Tests covering arithmetic builtin execution (add, sub, mul, div, mod, eq?, lt?, gt?),
string builtins (length, upcase, contains?, concat), list/pair builtins (list-length,
reverse, map, pair-fst-snd), bool builtins (and, or, not), let+match expressions,
effects dispatch (do+print, ability_key, empty handler), property checking, spelling
suggestions, typecheck multi-ref, elaborate guard+handle, Mnesia lifecycle,
storage stress (1000-insert, DETS survive), lexer token positions and complex escapes,
parser nested patterns and use rest, compile guarded match and TypeDef/AbilityDecl,
loader dual modules, and cross-module integration.

All levels are real implementations in `src/dogfood_v11.gleam`.

---

## Level 1451–1458: Arithmetic Builtins

**Level 1451** — `(add 2 3)` via `library_eval`.
- **Expected:** Returns `"5"`.

**Level 1452** — `(sub 10 3)` via `library_eval`.
- **Expected:** Returns `"7"`.

**Level 1453** — `(mul 6 7)` via `library_eval`.
- **Expected:** Returns `"42"`.

**Level 1454** — `(div 20 4)` via `library_eval`.
- **Expected:** Returns `"5"`.

**Level 1455** — `(mod 10 3)` via `library_eval`.
- **Expected:** Returns `"1"`.

**Level 1456** — `(eq? 5 5)` and `(eq? 5 6)` via `library_eval`.
- **Expected:** Returns `"1"` then `"0"`.

**Level 1457** — `(lt? 3 5)` and `(gt? 5 3)` via `library_eval`.
- **Expected:** Both return `"1"`.

**Level 1458** — `((lam x (add x 1)) 41)` via `library_eval`.
- **Expected:** Returns `"42"`.

---

## Level 1459–1462: String Builtins

**Level 1459** — `(string-length "hello")` via `library_eval`.
- **Expected:** Returns `"5"`.

**Level 1460** — `(string-upcase "hello")` via `library_eval`.
- **Expected:** Returns `"HELLO"`.

**Level 1461** — `(string-contains? "hello world" "world")` via `library_eval`.
- **Expected:** Returns `"1"`.

**Level 1462** — `(string-concat "hello " "world")` via `library_eval`.
- **Expected:** Returns `"hello world"`.

---

## Level 1463–1466: List + Pair Builtins

**Level 1463** — `(list-length (list 1 2 3 4 5))` via `library_eval`.
- **Expected:** Returns `"5"`.

**Level 1464** — `(list-reverse (list 1 2 3))` via `library_eval`.
- **Expected:** Returns reversed list.

**Level 1465** — `(list-map (lam x (mul x 2)) (list 1 2 3))` via `library_eval`.
- **Expected:** Returns `[2,4,6]`.

**Level 1466** — `(fst (pair 1 2))` and `(snd (pair 1 2))` via `library_eval`.
- **Expected:** Returns `"1"` and `"2"`.

---

## Level 1467–1468: Bool Builtins

**Level 1467** — `(and 1 0)` and `(or 0 1)` via `library_eval`.
- **Expected:** Returns `"0"` and `"1"`.

**Level 1468** — `(not 1)` and `(not 0)` via `library_eval`.
- **Expected:** Returns `"0"` and `"1"`.

---

## Level 1469–1471: Let + Match Expressions

**Level 1469** — `(let x (add 1 2) (let y (mul x 3) (add x y)))` via `library_eval`.
- **Expected:** Returns `"12"` (3 + 9).

**Level 1470** — `(match 42 (1 "one") (42 "found") (_ "other"))` via `library_eval`.
- **Expected:** Returns `"found"`.

**Level 1471** — `(match 99 (x x))` via `library_eval`.
- **Expected:** Returns `"99"`.

---

## Level 1472–1475: Effects Dispatch

**Level 1472** — `(do Console print "hello from v11")` via `library_eval`.
- **Expected:** Prints to stdout, eval returns result.

**Level 1473** — Compute `ability_key` format for `builtin_state_get`.
- **Expected:** Returns `"m_"` + 8-char hex suffix (10 chars total).

**Level 1474** — `effects_run(RuntimeConfig([]), fn() { 123 })`.
- **Expected:** Returns `Dynamic(123)`.

**Level 1475** — Single HandlerFrame with op handler.
- **Expected:** Thunk returns `Dynamic(1)`, handler returns `Dynamic(99)`.

---

## Level 1476–1478: Property + Spelling

**Level 1476** — Property check with `x >= 0` (always true).
- **Expected:** Returns `Ok(_)`.

**Level 1477** — Spelling: exact match `"secret"` in prev_defs with `"secret"` defined.
- **Expected:** `do_eval` returns `Ok("42", _, _)`.

**Level 1478** — Spelling: `"comupte"` (distance 2 from `"compute"`).
- **Expected:** Error contains `"Did you mean: compute?"`.

---

## Level 1479–1481: Typecheck + Elaborate

**Level 1479** — Multi-def unit: def1=Int(99):Int, def2=RefTo(def1):Int.
- **Expected:** Both insert into codebase successfully.

**Level 1480** — Parse+Elaborate: `(match 42 (x ? 1 x))` with guard.
- **Expected:** Elaborates to Unit successfully.

**Level 1481** — Parse+Elaborate: `(handle (do Console print "test") (lam x x) Console)`.
- **Expected:** Elaborates to Unit or errors appropriately.

---

## Level 1482–1485: Storage Deeper

**Level 1482** — Mnesia adapter: create → insert → lookup → close.
- **Expected:** Insert and lookup succeed (or open fails gracefully).

**Level 1483** — In-memory: insert 1000 refs via tail recursion.
- **Expected:** All 1000 inserts succeed without crash.

**Level 1484** — DETS: insert → close → reopen → lookup.
- **Expected:** Data survives close/reopen cycle.

**Level 1485** — In-memory `list_refs()` after 2 inserts.
- **Expected:** Returns at least 2 refs.

---

## Level 1486–1489: Lexer + Parser

**Level 1486** — Tokenize `"(let\\n  x\\n  42)"` and verify first token position.
- **Expected:** First token is `LParen` at line 1.

**Level 1487** — Tokenize `"\"a\\\\n\""` (complex escape combination).
- **Expected:** At least 1 token produced.

**Level 1488** — Parse nested constructor patterns.
- **Expected:** `(match (pair 1 (pair 2 3)) ((pair a (pair b c)) (add a b)))` parses successfully.

**Level 1489** — Parse `(use (x rest) (lam f (f 1 2 3)) (add x 1))`.
- **Expected:** Use with rest binder (`(use (x rest) call body)`) parses successfully.

---

## Level 1490–1492: Compile + Load

**Level 1490** — Compile guarded match: `Match(42, [Case(42, Some(1), 100), Case(0, None, 0)])`.
- **Expected:** Produces BEAM bytes.

**Level 1491** — Compile `TypeDef` + `AbilityDecl`.
- **Expected:** Both produce BEAM bytes.

**Level 1492** — Loader with 2 modules: load r1, load r2, verify both loaded.
- **Expected:** `is_loaded(r1)` and `is_loaded(r2)` both True.

---

## Level 1493–1500: Integration Certification

**Level 1493** — `(add (mul 2 3) (sub 10 5))` via `library_eval`.
- **Expected:** Returns `"11"` (6 + 5).

**Level 1494** — `(string-slice "hello world" 0 5)` via `library_eval`.
- **Expected:** Returns `"hello"`.

**Level 1495** — `(list-filter (lam x (gt? x 5)) (list 1 6 3 8 2))` via `library_eval`.
- **Expected:** Returns `[6,8]`.

**Level 1496** — `(list-length (list-map (lam x (add x 10)) (list 1 2 3)))` via `library_eval`.
- **Expected:** Returns `"3"`.

**Level 1497** — Storage + Lexer + Compile cross: insert, tokenize, compile.
- **Expected:** All 3 modules exercise without crash.

**Level 1498** — Effects + Typecheck + Log + Counter + JSON cross.
- **Expected:** All 5 modules exercise without crash.

**Level 1499** — Batch 11 summary.
- **Expected:** Prints 50-level summary.

**Level 1500** — v2.3 full certification: 521 total real dogfood levels, 51 unit tests, 572 total conformance verifications across 13 playbook files.
- **Expected:** Prints final certification banner.
