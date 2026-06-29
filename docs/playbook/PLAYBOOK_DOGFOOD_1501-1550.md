# Dogfooding Playbook — Levels 1501–1550

Tests covering all remaining builtins (string-downcase, string-replace, string-trim, string->int, string-split, list-append, list-member?, list-flatten, list-fold, list-sort, range, left/right, dict-new/get/set, set-new/insert, json-parse), recursive functions (factorial, sum-to, mutual recursion even/odd), higher-order functions (apply-twice, compose, lambda capture), compile pattern edges (PatText, unused var, PatCons, PatEmptyList), guard elaboration, push sync adapter filtering, idempotent insert, 1000-def stress, multiple define, effects handler args, complex nested eval, multi-line lexer, loader 10-module stress, DETS list_refs, jet misses, all pattern types compilation, and cross-module integration.

All levels are real implementations in `src/dogfood_v12.gleam`.

---

## Level 1501–1505: Remaining String Builtins

**Level 1501** — `(string-downcase "HELLO")` via `library_eval`.
- **Expected:** Returns `"hello"`.

**Level 1502** — `(string-replace "abxab" "ab" "xy")` via `library_eval`.
- **Expected:** Returns `"xyxxy"`.

**Level 1503** — `(string-trim "  hello  ")` via `library_eval`.
- **Expected:** Returns `"hello"`.

**Level 1504** — `(string->int "42")` via `library_eval`.
- **Expected:** Returns `"42"`.

**Level 1505** — `(string-split "a,b,c" ",")` via `library_eval`.
- **Expected:** Returns list of 3 strings.

---

## Level 1506–1511: Remaining List Builtins

**Level 1506** — `(list-append (list 1 2) (list 3 4))` via `library_eval`.
- **Expected:** Returns `(1 2 3 4)`.

**Level 1507** — `(list-member? 3 (list 1 2 3 4))` via `library_eval`.
- **Expected:** Returns `"1"` (truthy).

**Level 1508** — `(list-flatten (list (list 1 2) (list 3) (list 4 5)))` via `library_eval`.
- **Expected:** Returns `(1 2 3 4 5)`.

**Level 1509** — `(list-fold (lam acc (lam x (add acc x))) 0 (list 1 2 3 4))` via `library_eval`.
- **Expected:** Returns `"10"`.

**Level 1510** — `(list-sort (lam a (lam b (lt? a b))) (list 5 2 4 1 3))` via `library_eval`.
- **Expected:** Returns sorted list of length 5.

**Level 1511** — `(range 1 5)` via `library_eval`.
- **Expected:** Returns list of length 5.

---

## Level 1512–1515: Data Structure Builtins

**Level 1512** — `(left "hello")` and `(right "world")` via `library_eval`.
- **Expected:** Returns Left and Right tagged values.

**Level 1513** — `(dict-get (dict-set (dict-new) "key" "val") "key")` via `library_eval`.
- **Expected:** Returns `(just "val")`.

**Level 1514** — `(set-insert (set-new) 42)` via `library_eval`.
- **Expected:** Returns set containing 42.

**Level 1515** — `(json-parse "{\"a\":1}")` via `library_eval`.
- **Expected:** Returns parsed dict.

---

## Level 1516–1520: Recursion + Higher-Order Functions

**Level 1516** — Factorial: `fact 5`.
- **Expected:** Returns `"120"`.

**Level 1517** — Apply-twice: `((lam f (lam x (f (f x)))) (lam x (mul x 2)) 3)`.
- **Expected:** Returns `"12"`.

**Level 1518** — Compose: `((lam f (lam g (lam x (f (g x))))) inc double 5)`.
- **Expected:** Returns `"11"`.

**Level 1519** — Sum-to recursion: `(sum-to 10)`.
- **Expected:** Returns `"55"`.

**Level 1520** — Mutual recursion even/odd: `(even? 4)`.
- **Expected:** Returns `"1"`.

---

## Level 1521–1524: Compile Pattern Edges

**Level 1521** — Compile match with `PatText(<<"hello">>)` pattern.
- **Expected:** Produces BEAM bytes.

**Level 1522** — Compile match with unused `PatVar` (V0 not referenced in body).
- **Expected:** Produces BEAM bytes; `emit_pattern_body_aware` emits `"_"`.

**Level 1523** — Compile match with `PatCons(Local(0), Local(1))`.
- **Expected:** Produces BEAM bytes.

**Level 1524** — Compile match with `PatEmptyList`.
- **Expected:** Produces BEAM bytes.

---

## Level 1525–1529: Guard + Sync + Codebase

**Level 1525** — Parse+Elaborate match with guard `(match 42 (x ? 1 x))`.
- **Expected:** Guard elaborates correctly.

**Level 1526** — Push sync with ref not in adapter.
- **Expected:** Count should be 0 (ref silently filtered).

**Level 1527** — Idempotent insert: insert same def twice.
- **Expected:** Second insert returns Ok (no DuplicateDef error).

**Level 1528** — Codebase 1000-def insert stress.
- **Expected:** All 1000 inserts succeed.

**Level 1529** — REPL: define `a=10`, then `b=20`.
- **Expected:** Both defines succeed; cache contains both.

---

## Level 1530–1532: Effects + Inference

**Level 1530** — Effects handler receives and reports args count.
- **Expected:** Handler reports 0 args, returns `Dynamic(42)`.

**Level 1531** — Complex nested eval: `list-length(list-filter(gt? 3)(list-map(double)(list 1 2 3 4 5)))`.
- **Expected:** Returns result without crash.

**Level 1532** — Lexer tokenizes multi-line string with actual `\n` characters.
- **Expected:** Produces at least 1 token (not split across lines).

---

## Level 1533–1536: Loader + Storage + Jets + Patterns

**Level 1533** — Loader: load 10 identity lambda modules.
- **Expected:** All 10 loads succeed.

**Level 1534** — DETS list_refs after 2 inserts.
- **Expected:** Returns at least 2 refs.

**Level 1535** — Jet miss on 3 random hashes.
- **Expected:** All 3 return None.

**Level 1536** — Compile match with all 5 pattern types (Int, Text, Cons, EmptyList, Var).
- **Expected:** Produces BEAM bytes.

---

## Level 1537–1540: Builtin + Cross

**Level 1537** — Multi-let: `(let x 5 (let y 5 (mul x y)))`.
- **Expected:** Returns `"25"`.

**Level 1538** — Conditional: `(let is-even (lam n (eq? (mod n 2) 0)) (is-even 4))`.
- **Expected:** Returns `"1"`.

**Level 1539** — Chain: filter+mapped list operations.
- **Expected:** Returns correct length.

**Level 1540** — String-bool combo: `(and (string-contains? ...) (eq? (string-length...) 3))`.
- **Expected:** Returns `"1"`.

---

## Level 1541–1550: Integration Certification

**Level 1541** — Parse → Elaborate → Compile → Load+Eval full pipeline.
- **Expected:** All stages succeed.

**Level 1542** — Loader + Compile + Storage + Lexer cross.
- **Expected:** All 4 modules exercise.

**Level 1543** — Effects + Codebase + Lexer cross.
- **Expected:** All 3 modules exercise.

**Level 1544** — Inference + Log + Counter + JSON + Crypto cross.
- **Expected:** All 5 modules exercise.

**Level 1545** — REPL evaluate with all numeric builtins: `add(mul(sub(10,3),div(20,4)),mod(17,3))`.
- **Expected:** Returns `"37"`.

**Level 1546** — REPL nested comparisons: `(and (lt? 3 5) (and (gt? 10 9) (eq? (add 2 2) 4)))`.
- **Expected:** Returns `"1"`.

**Level 1547** — REPL list operations stress: sort and reverse 9 elements.
- **Expected:** Returns `"9"`.

**Level 1548** — REPL lambda capture: `(make-adder 5)` applied to 10.
- **Expected:** Returns `"15"`.

**Level 1549** — Batch 12 summary.
- **Expected:** Prints 50-level summary.

**Level 1550** — v2.4 full certification: 571 total real dogfood levels, 51 unit tests, 622 total conformance verifications across 14 playbook files.
- **Expected:** Prints final certification banner.
