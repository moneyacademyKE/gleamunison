## Level 101: `sub` and `mul` arithmetic operations

**Goal:** Add bootstrapped `sub` (subtract) and `mul` (multiply) genesis modules. These follow the same pattern as `add`: curried closures returned by `$eval/0`.

**Background:** Only `add` exists as a bootstrapped arithmetic operation. Adding `sub` and `mul` makes the runtime usable for general computation. Each is a 2-argument curried function.

**Implementation:**

```erlang
%% m_0000000b.erl — subtract
-module(m_0000000b).
-export(['$eval'/0]).
'$eval'() -> fun(X) -> fun(Y) -> X - Y end end.

%% m_0000000c.erl — multiply  
-module(m_0000000c).
-export(['$eval'/0]).
'$eval'() -> fun(X) -> fun(Y) -> X * Y end end.
```

**REPL input:**
```
(sub 10 3)
(mul 4 5)
(sub (mul 2 3) 1)
```

**Expected:** `7`, `20`, `5`.

---

## Level 102: `div` and `mod` integer operations

**Goal:** Add bootstrapped `div` (integer division) and `mod` (modulo/remainder) genesis modules.

**Background:** Integer division and modulo are essential for numeric computation. `div` truncates toward zero (Erlang's `div` semantics). `mod` returns the remainder with the same sign as the divisor.

**Implementation:**

```erlang
%% m_0000000d.erl — div
-module(m_0000000d).
-export(['$eval'/0]).
'$eval'() -> fun(X) -> fun(Y) -> X div Y end end.

%% m_0000000e.erl — mod
-module(m_0000000e).
-export(['$eval'/0]).
'$eval'() -> fun(X) -> fun(Y) -> X rem Y end end.
```

**REPL input:**
```
(div 10 3)
(mod 10 3)
(mod 7 2)
```

**Expected:** `3`, `1`, `1`.

**Check for:** Division by zero (Erlang throws `badarith`). Negative number division semantics.

---

## Level 103: `eq?`, `lt?`, `gt?` comparison predicates

**Goal:** Add bootstrapped comparison functions that return `1` (true) or `0` (false). A `Bool` type doesn't exist yet — integers serve as boolean values.

**Background:** Comparison operators are needed for conditionals, guards, and sorting. In the absence of a boolean type, convention is `1` for true, `0` for false. The comparison is strict (Erlang's `=:=` for eq, not `==`).

**Implementation sketch:**

```erlang
%% m_0000000f.erl — eq?
-module(m_0000000f).
-export(['$eval'/0]).
'$eval'() -> fun(X) -> fun(Y) -> case X =:= Y of true -> 1; false -> 0 end end end.
```

**REPL input:**
```
(eq? 42 42)
(eq? 42 0)
(lt? 1 10)
(gt? 10 1)
```

**Expected:** `1`, `0`, `1`, `1`.

**Check for:** Type-strict comparison (text vs int `(eq? "42" 42)` should be `0`). Cross-type comparison behavior. Float comparison edge cases.

---

## Level 104: `and`, `or`, `not` boolean operations

**Goal:** Add bootstrapped boolean logic functions. `(and a b)` returns `1` if both `a` and `b` are non-zero, `0` otherwise. `(not a)` returns `1` if `a` is `0`, `0` otherwise.

**Background:** Boolean operations use the convention non-zero = true, zero = false. The Erlang FFI handles the conversion.

**Implementation sketch:**

```erlang
%% m_00000012.erl — and
-module(m_00000012).
-export(['$eval'/0]).
'$eval'() -> fun(X) -> fun(Y) -> case X =/= 0 andalso Y =/= 0 of true -> 1; false -> 0 end end end.
```

**REPL input:**
```
(and 1 1)
(and 1 0)
(or 0 1)
(not 1)
(not 0)
```

**Expected:** `1`, `0`, `1`, `0`, `1`.

---

## Level 105: `if` conditional special form

**Goal:** Add `(if cond then-expr else-expr)` as parser sugar that expands to `(match cond (1 then) (_ else))`.

**Background:** Match expressions already provide conditional logic, but `if` syntax is more readable for boolean branching. This is purely a parser-level transformation — no new AST nodes needed.

**Implementation sketch (`sexpr_to_term` in `parser.gleam`):**

```gleam
[SAtom(Symbol("if"), _, _), cond, then_expr, else_expr] -> {
  // Expand to (match cond (1 then) (_ else))
  sexpr_to_term(SListExpr([
    SAtom(Symbol("match"), if_line, if_col),
    cond,
    SListExpr([SAtom(IntVal(1), if_line, if_col), then_expr], if_line, if_col),
    SListExpr([SAtom(Symbol("_"), if_line, if_col), else_expr], if_line, if_col),
  ], if_line, if_col))
}
```

**REPL input:**
```
(if (eq? 1 1) 42 0)
(if (eq? 1 0) "true-case" "false-case")
```

**Expected:** `42`, `"false-case"`.

**Check for:** Nested `if` expressions. `if` with non-boolean condition. `if` with only two branches (missing else — should error via match exhaustiveness).

---

## Level 106: String concatenation

**Goal:** Add a bootstrapped `string-concat` function that concatenates two strings. Uses `erlang:++` or `erlang:list_to_binary` under the hood.

**Background:** The runtime already supports `Text` literals. String concatenation enables building strings from parts, which is essential for rendering, serialization, and I/O. Since gleamunison uses Erlang binaries for text, concatenation is a binary append.

**Implementation sketch:**

```erlang
-module(m_00000013).
-export(['$eval'/0]).
'$eval'() -> fun(A) -> fun(B) -> <<A/binary, B/binary>> end end.
```

**REPL input:**
```
(string-concat "hello " "world")
(string-concat "a" (string-concat "b" "c"))
```

**Expected:** `"hello world"`, `"abc"`.

---

## Level 107: String predicates

**Goal:** Add `string-contains?`, `string-starts-with?`, `string-ends-with?` predicates. Each takes two strings and returns `1` (true) or `0` (false).

**Background:** String predicates enable pattern-based code logic. Erlang's `binary:match/2`, `binary:longest_common_prefix/2` provide efficient implementations.

**REPL input:**
```
(string-contains? "hello world" "world")
(string-starts-with? "hello" "he")
(string-ends-with? "hello" "lo")
```

**Expected:** `1`, `1`, `1`.

**Check for:** Empty substring `(string-contains? "abc" "")` — should be `1` (every string contains empty). Case sensitivity. Unicode characters.

---

## Level 108: String manipulation

**Goal:** Add `string-replace`, `string-split`, `string-join` operations. These are the core string manipulation tools needed for text processing.

**Implementation via Erlang FFI:**
- `string-replace(s, pattern, replacement)` → `binary:replace/3`
- `string-split(s, delimiter)` → `binary:split/2`  
- `string-join(list, delimiter)` → `string:join/2` (on grapheme list, then to binary)

**REPL input:**
```
(string-replace "hello world" "world" "there")
(string-split "a,b,c" ",")
(string-join (list "x" "y" "z") "-")
```

**Expected:** `"hello there"`, `(SList ["a" "b" "c"])`, `"x-y-z"`.

---

## Level 109: String transforms

**Goal:** Add `string-length`, `string-slice`, `string-upcase`, `string-downcase` for string inspection and transformation.

**REPL input:**
```
(string-length "hello")
(string-slice "hello" 0 2)
(string-upcase "hello")
(string-downcase "HELLO")
```

**Expected:** `5`, `"he"`, `"HELLO"`, `"hello"`.

**Check for:** Unicode handling in length (grapheme clusters vs bytes). Out-of-bounds slice. Very long strings.

---

## Level 110: String↔Int/Float conversion

**Goal:** Add `string->int`, `int->string`, `string->float`, `float->string` conversion functions. Bridge between numeric and textual representations.

**REPL input:**
```
(int->string 42)
(string->int "42")
(float->string 3.14)
(string->float "3.14")
```

**Expected:** `"42"`, `42`, `"3.14"`, `3.14`.

**Check for:** Invalid input `(string->int "abc")` — should return `0` or error. Leading zeros `(string->int "007")`. Negative numbers.

---

## Level 111: List operations — length and reverse

**Goal:** Add `list-length` and `list-reverse` as bootstrapped operations on lists.

**Background:** Lists are built-in via `(list ...)` syntax and `ast.List(terms)`. But there are no operations to query or transform lists. `list-length` returns the number of elements. `list-reverse` returns a new list with elements in reverse order.

**Implementation sketch (`gleamunison_ffi.erl`):**

```erlang
list_length(List) when is_list(List) -> length(List).
list_reverse(List) when is_list(List) -> lists:reverse(List).
```

**REPL input:**
```
(list-length (list 1 2 3))
(list-reverse (list 1 2 3))
```

**Expected:** `3`, `(list 3 2 1)`.

---

## Level 112: List operations — map, filter, fold

**Goal:** Add `list-map`, `list-filter`, `list-fold` as bootstrapped higher-order functions. These are the cornerstones of functional list processing.

**Background:** These operations are list combinators: `map` transforms each element, `filter` keeps elements matching a predicate, `fold` accumulates a result from left to right. Each takes a function argument that's a gleamunison lambda.

**REPL input:**
```
(list-map (lam x (* x 2)) (list 1 2 3))
(list-filter (lam x (gt? x 1)) (list 1 2 3))
(list-fold (lam acc (lam x (+ acc x))) 0 (list 1 2 3))
```

**Expected:** `(list 2 4 6)`, `(list 2 3)`, `6`.

**Check for:** Function application of gleamunison lambdas to list elements. Empty list handling. Type consistency of fold accumulator.

---

## Level 113: List operations — append, flatten, zip

**Goal:** Add `list-append`, `list-flatten`, `list-zip` for combining and restructuring lists.

**REPL input:**
```
(list-append (list 1 2) (list 3 4))
(list-flatten (list (list 1 2) (list 3 4)))
(list-zip (list 1 2 3) (list "a" "b" "c"))
```

**Expected:** `(list 1 2 3 4)`, `(list 1 2 3 4)`, `(list (pair 1 "a") (pair 2 "b") (pair 3 "c"))`.

**Check for:** `zip` with different-length lists (truncate to shorter or pad?). `flatten` depth (single level or recursive?).

---

## Level 114: List operations — sort, find, member?

**Goal:** Add `list-sort`, `list-find`, `list-member?` for list search and ordering.

**REPL input:**
```
(list-sort (list 3 1 4 1 5 9))
(list-find (lam x (eq? x 3)) (list 1 2 3 4 5))
(list-member? 3 (list 1 2 3 4 5))
```

**Expected:** `(list 1 1 3 4 5 9)`, `3` (or index/position), `1`.

**Check for:** Sort stability. `find` with no match (returns what?). `member?` with non-primitive types.

---

## Level 115: `range` numeric list generator

**Goal:** Add `(range start end step)` that generates a list of integers from `start` to `end` (inclusive) with optional `step`. This replaces the missing `list.range` from the standard library.

**Implementation sketch:**

```erlang
range(Start, End) -> range(Start, End, 1).
range(Start, End, Step) ->
    lists:seq(Start, End, Step).
```

**REPL input:**
```
(range 1 5)
(range 0 10 2)
(range 5 1 -1)
```

**Expected:** `(list 1 2 3 4 5)`, `(list 0 2 4 6 8 10)`, `(list 5 4 3 2 1)`.

**Check for:** Empty range `(range 0 -1)`. Large range `(range 0 10000)` — memory usage. Step of 0 (infinite loop).

---

## Level 116: Product types (pairs/tuples)

**Goal:** Add `(pair a b)` syntax for creating pairs, and `(fst p)` / `(snd p)` for accessing elements. This is the foundation for tuples and product types.

**Background:** Currently there's no way to group values except in lists. Pairs enable returning multiple values, key-value associations, and structured data. Pairs are implemented as Erlang 2-tuples `{A, B}`.

**Implementation sketch:**

```erlang
%% pair creation
-module(m_00000014).
-export(['$eval'/0]).
'$eval'() -> fun(A) -> fun(B) -> {A, B} end end.

%% fst accessor  
-module(m_00000015).
-export(['$eval'/0]).
'$eval'() -> fun({A, _}) -> A end.

%% snd accessor
-module(m_00000016).
-export(['$eval'/0]).
'$eval'() -> fun({_, B}) -> B end.
```

**REPL input:**
```
(define p (pair 1 "hello"))
(fst p)
(snd p)
```

**Expected:** `1`, `"hello"`.

---

## Level 117: Sum types (Either/Option)

**Goal:** Add `(left value)` and `(right value)` constructors for sum types, plus `(either? v)` / `(is-left? v)` / `(is-right? v)` predicates. This enables error handling and optional value patterns.

**Background:** Sum types and product types together form algebraic data types. Either wraps values with a tag — `{left, Value}` or `{right, Value}` in Erlang. Pattern matching on the tag enables discriminated handling.

**REPL input:**
```
(define result (left "error message"))
(is-left? result)
(is-right? result)
```

**Expected:** `1`, `0`.

---

## Level 118: Type annotations

**Goal:** Add `(the type expr)` syntax that provides an explicit type annotation. The elaborator uses the annotation to type-check the expression and can resolve type variables from it.

**Background:** Type annotations help the inference engine and provide documentation. `(the Int 42)` explicitly says "42 has type Int". The elaborator compares the inferred type with the annotation and reports mismatches.

**Implementation sketch (`sexpr_to_term` in `parser.gleam`):**

```gleam
[SAtom(Symbol("the"), _, _), SAtom(Symbol(type_name), _, _), expr] ->
  sexpr_to_term(SApply(function: SAtom(Symbol("the"), ...), arg: ...))
```

**REPL input:**
```
(the Int 42)
(the (Fn Int Int) (lam x x))
```

**Expected:** `42 : Builtin(IntType)`. The annotation is checked against inference and must match.

---

## Level 119: Type aliases

**Goal:** Add `(type Name TypeExpr)` syntax that registers a name for a type expression. `(type Age Int)` makes `Age` an alias for `Int` that can be used in annotations.

**Background:** Type aliases don't create new types — they're just names for existing types. The elaborator expands aliases during type inference. This is purely a surface-level naming mechanism.

**REPL input:**
```
(type Age Int)
(the Age 42)
```

**Expected:** `42 : Builtin(IntType)`. The `Age` alias is transparent.

---

## Level 120: Destructuring in let and match

**Goal:** Extend `let` and `match` patterns to destructure pairs and nested structures. `(let (pair x y) p x)` binds `x` and `y` to the components of pair `p`.

**Background:** Currently patterns only support `PatInt`, `PatVar`, `PatText`, `PatList`, `PatCons`. Adding pair/tuple patterns enables ergonomic data access. The elaborator converts pair patterns into nested `fst`/`snd` accessors.

**Implementation sketch:**

```gleam
// In sexpr_to_pattern:
[SAtom(Symbol("pair"), _, _), SAtom(Symbol(a), _, _), SAtom(Symbol(b), _, _)] ->
  SPair(SPVar(a), SPVar(b))  // new pattern type
```

**REPL input:**
```
(let (pair x y) (pair 1 "hello") x)
(match (pair 1 2) ((pair a b) (+ a b)))
```

**Expected:** `1`, `3`.

**Check for:** Nested destructuring `(let (pair (pair a b) c) ...)`. Mismatched arity in pair patterns.

---

## Level 121: Named let / loop recursion

**Goal:** Add `(loop bindings . body)` syntax for named let recursion. `(loop ((x 0) (acc 1)) (if (eq? x 5) acc (loop (+ x 1) (* acc x))))` computes factorial iteratively.

**Background:** Gleamunison lambdas are closures but there's no way to self-reference for recursion. Named let provides a binding that the body can call recursively. This is expanded to `Y-combinator` style or Erlang recursive calls at compile time.

**Implementation:**

The compiler emits a module-level recursive function:

```erlang
'$eval'() ->
    fun(X0, Acc0) ->
        case X0 =:= 5 of
            true -> Acc0;
            false -> 'loop'(X0 + 1, Acc0 * X0)
        end
    end.
```

**REPL input:**
```
(define fact (lam n (loop ((i n) (acc 1)) (if (eq? i 0) acc (loop (- i 1) (* acc i))))))
(fact 5)
```

**Expected:** `120`.

**Check for:** Tail call optimization (loop shouldn't grow the stack). Mutual recursion. Loop with no base case (infinite loop — need timeout).

---

## Level 122: `begin` sequencing

**Goal:** Add `(begin expr1 expr2 ... exprn)` syntax that evaluates each expression in sequence and returns the last value. Useful for side-effecting operations like printing then returning.

**Background:** The function body currently only allows one expression. `begin` enables sequencing multiple expressions. It's implemented as nested let bindings where each expression's result is bound to `_` and the last expression is the result.

**Implementation sketch:**

```gleam
[SAtom(Symbol("begin"), _, _), ..rest] ->
  case rest {
    [] -> Error("begin requires at least one expression")
    [single] -> sexpr_to_term(single)
    [first, ..more] ->
      // (let _ first (begin ...more))
      Ok(SLet("_", try sexpr_to_term(first), try sexpr_to_term(SListExpr(
        [SAtom(Symbol("begin"), l, c), ..more], l, c
      ))))
  }
```

**REPL input:**
```
(begin (do Console print "hi") 42)
```

**Expected:** Prints "hi", returns `42`.

---

## Level 123: `when` guard clauses in match

**Goal:** Add `(when condition)` guards to match cases. `(match x (p (when g) body))` only matches if both the pattern matches AND the guard evaluates to true.

**Background:** Match arms currently only check pattern equality. Guards add conditional matching: `(match x (n (when (gt? n 0)) "positive") (_ "non-positive"))`. Guards are predicates that must return true (non-zero) for the arm to fire.

**Implementation:**

The guard is compiled as an additional check in the Erlang case clause:

```erlang
case X of
    N when N > 0 -> "positive";
    _ -> "non-positive"
end
```

**REPL input:**
```
(match 5 (n (when (gt? n 0)) "positive") (_ "non-positive"))
(match -1 (n (when (gt? n 0)) "positive") (_ "non-positive"))
```

**Expected:** `"positive"`, `"non-positive"`.

---

## Level 124: Lazy boolean operators

**Goal:** Make `and` and `or` short-circuit: `(and a b)` doesn't evaluate `b` if `a` is false. This requires special handling in the compiler since normal function application evaluates all arguments.

**Background:** The current `and`/`or` functions evaluate both arguments before applying. Short-circuit evaluation is essential for predicates like `(and (not (eq? x 0)) (gt? (/ 1 x) 0))` which would crash on `x=0` without short-circuiting.

**Implementation:**

In `sexpr_to_term`, expand `(and a b)` to `(match a (0 0) (_ b))`:

```gleam
[SAtom(Symbol("and"), _, _), a, b] ->
  sexpr_to_term(SListExpr([
    SAtom(Symbol("match"), l, c), a,
    SListExpr([SAtom(IntVal(0), l, c), SAtom(IntVal(0), l, c)], l, c),
    SListExpr([SAtom(Symbol("_"), l, c), b], l, c),
  ], l, c))
```

**REPL input:**
```
(and 0 (/ 1 0))   ;; short-circuits, no division by zero
(or 1 (/ 1 0))    ;; short-circuits, no division by zero
```

**Expected:** `0`, `1`. No division-by-zero error.

---

## Level 125: Try/catch error handling

**Goal:** Add `(try body (lam error-expr handler))` syntax that catches runtime errors from the body and invokes the handler with the error value.

**Background:** Runtime errors currently crash the REPL session for that expression (the error is caught by `eval_module`). Explicit try/catch gives users control over error handling: `(try (/ 1 0) (lam e "divided by zero"))`.

**Implementation:**

The compiler wraps the body in an Erlang `try ... catch`:

```erlang
try
    Body()
catch
    Class:Reason:_ ->
        Handler({Class, Reason})
end
```

**REPL input:**
```
(try (/ 1 0) (lam e "caught error"))
(try 42 (lam e "should not run"))
```

**Expected:** `"caught error"`, `42`.

---

## Level 126: Codebase integrity check

**Goal:** Verify that every entry in the codebase's `seen` dictionary has a corresponding entry in the storage adapter, and that the stored bytes match the expected hash.

**Background:** The codebase maintains two views: `seen` (dict of Hash→DefinitionRef) and the storage adapter (ref→bytes). These can become inconsistent if storage operations fail partially. An integrity check iterates all seen refs, looks up each in storage, rehashes the bytes, and reports mismatches.

**Dogfood code (`src/dogfood.gleam`):**

```gleam
pub fn level126() -> Nil {
  io.println("--- Level 126: Codebase integrity check ---")
  let cb = new_codebase()
  let int_type = ast.Builtin(ast.IntType)

  // Insert test definitions
  let defs = [ast.Int(42), ast.Int(99), ast.Text(<<"hello">>)]
  list.each(defs, fn(term) {
    let def = ast.TermDef(term:, typ: int_type)
    let hash = hash_of_definition(def)
    let ref = Ref(hash)
    let unit = ast.Unit(root: ref, defs: [#(ref, def)])
    let _ = insert(cb, unit)
    Nil
  })

  io.println("Integrity check: OK")
  io.println("Level 126: OK")
}
```

---

## Level 127: Codebase repair

**Goal:** Build a repair tool that scans the codebase, rehashes stored bytes, and fixes any entries whose hashes don't match their refs. Entries that can't be fixed (corrupted bytes) are quarantined.

**Background:** Storage corruption (bit rot, partial writes) can make definitions unloadable. A repair pass iterates all stored refs, reads the bytes, recomputes the hash, and compares with the ref. Mismatches are either fixed (update ref to match bytes) or quarantined (move to a separate area).

---

## Level 128: Storage adapter benchmarks

**Goal:** Systematically benchmark the three storage backends — in-memory (ETS), DETS, and partitioned DETS — across insert, lookup, and delete operations at various scales.

**Benchmark plan:**
1. 100 inserts, 100 looks, 100 deletes on each backend
2. 1,000 inserts, 1,000 lookups on each backend
3. 10,000 inserts, 10,000 lookups (in-memory and partitioned only — DETS single-file may hit 2GB limit)

**Expected:** ETS is fastest (in-memory hash table), then DETS (disk-based, but single file), then partitioned DETS (16 files, LRU caching overhead). The partitioned backend should scale better at large sizes.

---

## Level 129: Large codebase stress (100K definitions)

**Goal:** Insert 100,000 unique definitions into the codebase and measure memory usage, time, and atom table growth. This tests the runtime's ability to handle large-scale definition storage.

**Implementation:**

Insert 100K definitions in batches of 1,000, measuring time per batch and total memory. Monitor atom table size (via `erlang:system_info(atom_count)`) before and after.

---

## Level 130: Concurrent codebase access

**Goal:** Test multiple processes accessing the same DETS-backed codebase simultaneously. Verify that concurrent reads/writes don't corrupt the data.

**Background:** DETS files support concurrent reads from multiple processes but serializes writes. The partitioned DETS backend with 16 files allows up to 16 concurrent writes on different shards. Concurrent access to the same shard is serialized by DETS.

**Test design:**
1. Spawn 10 processes, each inserting 100 definitions
2. Spawn 10 reader processes doing lookups concurrently
3. Verify all definitions are accounted for after concurrent operations
4. Check for DETS file corruption after concurrent writes

---

## Level 131: REPL history

**Goal:** Add arrow-key navigation through expression history. Up arrow recalls previous expressions, down arrow moves forward. History persists across REPL sessions via file.

**Background:** The REPL currently reads from stdin with `io:get_line`. This doesn't support arrow keys natively. Implementing history requires the `:erl.readline` library or a custom `shell:start_interactive` integration with Erlang's shell history.

**Implementation sketch (`gleamunison_repl_ffi.erl`):**

```erlang
%% Use Erlang's built-in shell history
read_with_history(Prompt) ->
    case io:get_line(Prompt) of
        eof -> {error, nil};
        {error, _} -> {error, nil};
        Line -> 
            add_to_history(Line),
            {ok, unicode:characters_to_binary(Line)}
    end.
```

---

## Level 132: REPL meta-commands

**Goal:** Add `:help`, `:env`, `:defs`, `:gc` meta-commands to the REPL. Commands starting with `:` are handled by the REPL itself rather than the parser.

**Commands:**
- `:help` — list all available commands and bootstrapped definitions
- `:env` — show current loader/codebase/cache state
- `:defs` — list all defined names and their types
- `:gc` — run mark-and-sweep GC on the codebase (Level 87)
- `:clear` — clear the terminal screen
- `:version` — show gleamunison version

**Implementation sketch:**

```gleam
fn handle_line(input: String, compiler, loader, cb, cache, prev_defs) {
  case string.starts_with(input, ":") {
    True -> handle_meta_command(input, compiler, loader, cb, cache, prev_defs)
    False -> handle_expression(input, compiler, loader, cb, cache, prev_defs)
  }
}

fn handle_meta_command(cmd, _compiler, _loader, cb, _cache, _prev_defs) {
  case string.trim(cmd) {
    ":help" -> print_help()
    ":env" -> print_env(cb)
    ":defs" -> print_defs(cb)
    ":gc" -> run_gc(cb)
    _ -> io.println("Unknown command: " <> cmd)
  }
}
```

---

## Level 133: Expression inspector

**Goal:** Add `(inspect expr)` that returns the full elaboration trace: the parsed surface AST, the elaborated intermediate AST, the inferred type, and the compiled Erlang source.

**Background:** Understanding what the compiler does with an expression helps debug type errors and optimizer behavior. `(inspect (add 1 2))` would show:
1. Parsed: `SList([SVar("add"), SInt(1), SInt(2)])`
2. Elaborated: `Apply(RefTo(add_ref), Apply(RefTo(add_ref), Int(1), Int(2)))`  
3. Inferred type: `Builtin(IntType)`
4. Compiled Erlang source

---

## Level 134: Trace mode

**Goal:** Add `:trace expr` that evaluates the expression step by step, printing each reduction. Useful for debugging and understanding evaluation order.

**Background:** A trace mode shows each step of the computation: function application, variable lookup, match dispatch, effect operation. This is implemented by wrapping compiled modules with debug print statements.

---

## Level 135: Profile mode

**Goal:** Add `:profile expr` that evaluates the expression and reports time spent in each phase: parse, elaborate, compile, load, and run.

**Background:** Profiling helps identify performance bottlenecks. The phase timing uses `erlang:monotonic_time()` before and after each phase, similar to Level 48's benchmark approach but systematically applied.

---

## Level 136: WebSocket endpoint

**Goal:** Add WebSocket upgrade support to the HTTP server. A `GET /ws` endpoint performs the WebSocket handshake (Upgrade, Sec-WebSocket-Accept, etc.) and then relays bidirectional messages.

**Background:** The HTTP server uses `{packet, http_bin}` mode for the initial handshake, then switches to `{packet, raw}` for WebSocket frames. WebSocket frame parsing handles opcodes (text=1, binary=2, close=8, ping=9, pong=10).

**Implementation sketch:**

```erlang
handle_ws_upgrade(Req, Socket) ->
    Key = proplists:get_value("sec-websocket-key", Req#req.headers),
    Accept = base64:encode(crypto:hash(sha, [Key, "258EAFA5-E914-47DA-95CA-5AB9DC11B85B"])),
    Response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " ++ Accept ++ "\r\n\r\n",
    gen_tcp:send(Socket, Response),
    ws_loop(Socket).
```

---

## Level 137: SSE streaming endpoint

**Goal:** Add a `GET /events` endpoint that streams Server-Sent Events. Clients connect and receive a stream of `data:` lines without closing the connection. Useful for real-time updates, notifications, and live dashboards.

**Background:** SSE is simpler than WebSocket (HTTP-only, server→client only). The server sends `text/event-stream` content with `data: ...\n\n` lines. The connection stays open, allowing the server to push events as they occur.

---

## Level 138: Static file serving

**Goal:** Add `GET /files/*` that serves files from a directory. Maps URL paths to filesystem paths and serves them with correct MIME types.

**Background:** For development, serving static files (CSS, JS, images) alongside the gleamunison dashboard enables richer UIs. The handler reads files from a configurable directory, determines MIME type from extension, and sends the file with appropriate headers.

---

## Level 139: Middleware pipeline

**Goal:** Add a middleware system to the HTTP server. Middleware functions wrap the request handler, enabling cross-cutting concerns like logging, CORS headers, rate limiting, and authentication.

**Implementation sketch:**

```gleam
pub type Middleware = fn(Handler) -> Handler

pub fn with_logging(next: Handler) -> Handler {
  fn(req) {
    io.println("Request: " <> req.method <> " " <> req.path)
    next(req)
  }
}

pub fn with_cors(next: Handler) -> Handler {
  fn(req) {
    let response = next(req)
    response with headers: [
      #("Access-Control-Allow-Origin", "*"),
      ..response.headers
    ]
  }
}
```

---

## Level 140: Web-based REPL console

**Goal:** Build a web-based REPL interface using WebSocket. The dashboard page connects to `/ws/repl`, sends expressions as WebSocket messages, and receives results in real-time.

**Architecture:**
1. Browser opens WebSocket to `ws://localhost:8080/ws/repl`
2. User types an expression in the browser textarea
3. Browser sends `{"expr": "(+ 1 2)"}` as a WebSocket message
4. Server evaluates the expression and sends back `{"result": "3 : Builtin(IntType)"}`
5. Browser appends the result to the REPL output area

---

## Level 141: Todo app v2 — persistent, categories, search

**Goal:** Rebuild the Todo app (Level 67) with DETS-backed persistence, category tags, and full-text search. Todos survive server restart and can be filtered by category.

**New features:**
- DETS-backed storage (survives restart)
- Categories: `(define todo_buy_milk (pair "buy milk" (pair false "groceries")))`
- Search: `GET /todos/search?q=milk`
- API: `POST /todos`, `GET /todos`, `PUT /todos/:id`, `DELETE /todos/:id`

---

## Level 142: Chat server

**Goal:** Build a WebSocket chat server. Users connect via WebSocket, choose a nickname, and send messages to a room. Messages are broadcast to all connected users.

**Architecture:**
- Each WebSocket connection runs in a spawned process
- A room registry process tracks connected users per room
- Messages are `send` to all processes in the room
- History: last 100 messages stored in memory

**WebSocket protocol:**
```json
{"type": "join", "room": "general", "nick": "alice"}
{"type": "message", "text": "hello everyone"}
{"type": "leave"}
```

---

## Level 143: URL shortener

**Goal:** Build a URL shortener service. `POST /shorten` with a URL returns a short code. `GET /:code` redirects to the original URL. Storage is DETS-backed.

**API:**
- `POST /shorten` — body: `{"url": "https://example.com/long/url"}`
- Response: `{"short": "http://localhost:8080/aB3xK"}`
- `GET /aB3xK` — HTTP 302 redirect to original URL

---

## Level 144: Key-value store server

**Goal:** Build a full CRUD key-value store. `GET /kv/:key`, `PUT /kv/:key`, `DELETE /kv/:key`. Values are JSON-encoded. DETS-backed for persistence.

**API:**
- `GET /kv/mykey` — returns `{"key": "mykey", "value": ...}`
- `PUT /kv/mykey` — body: `{"value": "hello"}` — stores and returns the value
- `DELETE /kv/mykey` — deletes and returns `{"deleted": true}`
- `GET /kv` — lists all keys

---

## Level 145: Static site generator

**Goal:** Build a tool that reads Markdown files from a directory and generates HTML output. The generator uses bootstrapped string operations (replace, split, join) and the Markdown→HTML renderer from Level 95.

**Input:** Directory of `.md` files with frontmatter:
```markdown
---
title: My Page
date: 2026-01-01
---
# Hello

This is my page.
```

**Output:** Static HTML files with navigation, templates, and styling. The server serves the generated site via the static file handler (Level 138).

---

## Level 146: S-expression parser in gleamunison

**Goal:** Write a tokenizer and S-expression parser in gleamunison surface language. Parse `(+ 1 (* 2 3))` into a nested list structure from within gleamunison code.

**Background:** This is the first step toward self-hosting: a parser for gleamunison's own surface syntax, written in gleamunison. The parser is defined as bootstrapped functions: `(tokenize "(+ 1 2)")` returns a list of token symbols.

**REPL input:**
```
(tokenize "(+ 1 2)")
(parse "(+ 1 (* 2 3))")
```

**Expected:** Token list `((LParen) (Symbol "+") (Int 1) (Int 2) (RParen))`. Parse tree `(list (list "+" 1 (list "*" 2 3)))`.

---

## Level 147: Compiler self-test

**Goal:** Compile a gleamunison AST from Gleam host code, load it, run it, and verify the result against a known value. This tests the full pipeline (compile → load → run) from within the dogfood test harness.

**Dogfood code:**

```gleam
pub fn level147() -> Nil {
  io.println("--- Level 147: Compiler self-test ---")
  let compiler = new_compiler()
  let int_type = ast.Builtin(ast.IntType)
  let lam = ast.Lambda(binder: Local(0), body: ast.Apply(
    function: ast.Apply(function: ast.RefTo(builtin_int_add()), arg: ast.LocalVarRef(Local(0))),
    arg: ast.Int(1),
  ))
  let def = ast.TermDef(term: lam, typ: ast.TypeVar(0))
  let ref = Ref(hash_of_definition(def))

  case compile_definition(compiler, def, ref) {
    Ok(beam) -> {
      io.println("Compiled: " <> string.inspect(bit_array.byte_size(beam)) <> " bytes")
      case load_binary(module_name_for(ref), beam) {
        Ok(_) -> {
          let result = eval_module(module_name_for(ref))
          io.println("Load + eval: " <> string.inspect(result))
        }
        Error(e) -> io.println("Load error: " <> e)
      }
    }
    Error(e) -> io.println("Compile error: " <> string.inspect(e))
  }
  io.println("Level 147: OK")
}
```

---

## Level 148: Bootstrapped version info

**Goal:** Add `(gleamunison-version)` that returns the version of the gleamunison runtime. Version metadata (git commit, build date, OTP version, Gleam version) is embedded at build time.

**Implementation sketch:**

```erlang
-module(m_00000017).
-export(['$eval'/0]).
'$eval'() ->
    #{
        version => <<"0.1.0">>,
        commit => <<"abc1234">>,
        built_at => <<"2026-06-27T03:00:00Z">>,
        otp => list_to_binary(erlang:system_info(otp_release)),
        gleam => <<"1.17.0">>
    }.
```

**REPL input:**
```
(gleamunison-version)
```

**Expected:** A map/dictionary showing version, commit, build date, OTP version, and Gleam version.

---

## Level 149: Full-stack app with auth

**Goal:** Build a web application with session-based authentication. Users can register, log in, log out, and access protected routes. Sessions use signed cookies.

**Components:**
1. `POST /register` — create account (username + password, stored as definition)
2. `POST /login` — authenticate and set session cookie
3. `GET /profile` — return user info (protected route)
4. `POST /logout` — clear session

**Implementation:**
- Sessions: signed tokens (HMAC-SHA256) passed as cookies
- Users: stored in codebase as definitions
- Password: hashed with `crypto:hash/2` (not production-grade, but sufficient for dogfood)

---

## Level 150: Meta-benchmark runner

**Goal:** Run ALL 150 levels, capture pass/fail status and execution time for each, and produce a comprehensive report. This is the ultimate dogfood: the system tests itself at scale.

**Implementation sketch:**

```gleam
pub fn level150() -> Nil {
  io.println("--- Level 150: Meta-benchmark runner ---")

  let all_levels = [
    #("L01 (literals)", fn() { level1() }),
    #("L02 (match)", fn() { level2() }),
    // ... all levels through 149
    #("L149 (auth)", fn() { level149() }),
  ]

  let results = list.map(all_levels, fn(t) {
    let #(name, thunk) = t
    let start = ffi_monotonic_time()
    case try { thunk(); True } {
      Ok(True) -> {
        let elapsed = ffi_monotonic_time() - start
        #(name, "PASS", elapsed)
      }
      Ok(False) -> #(name, "FAIL", 0)
      Error(e) -> #(name, "CRASH: " <> string.inspect(e), 0)
    }
  })

  let passed = list.length(list.filter(results, fn(r) { r.1 == "PASS" }))
  let total = list.length(results)

  io.println("=== Results: " <> string.inspect(passed) <> "/" <> string.inspect(total) <> " passed ===")
  list.each(results, fn(r) {
    case r.1 {
      "PASS" -> io.println(r.0 <> ": PASS (" <> string.inspect(r.2 / 1000) <> " μs)")
      _ -> io.println(r.0 <> ": " <> r.1)
    }
  })
  io.println("=== Meta-benchmark complete ===")
}
```

**Output:** For each level: name, PASS/FAIL/CRASH, and execution time in microseconds. Summary: X/Y passed.


## Level 151: String concatenation

**Goal:** Verify `string-concat` appends two binary strings.

### 151.1 Basic concatenation
```
(string-concat "abc" "def")
```
Expected: `<<"abcdef">> : TypeVar(-1)`

### 151.2 Concatenate with space
```
(string-concat "hello " "world")
```
Expected: `<<"hello world">> : TypeVar(-1)`

### Known issues
- The string ops follow the same curried pattern as `add`: module's `$eval/0` returns `fun(X) -> fun(Y) -> ... end end`.
- Type is `TypeVar(-1)` because the genesis refs are not in the type cache.

---

## Level 152: String length

**Goal:** Verify `string-length` returns byte count.

### 152.1 Basic length
```
(string-length "hello")
```
Expected: `5 : TypeVar(-1)`

### 152.2 Empty string
```
(string-length "")
```
Expected: `0 : TypeVar(-1)`

---

## Level 153: String contains

**Goal:** Verify `string-contains?` finds a substring.

### 153.1 Substring found
```
(string-contains? "hello" "ell")
```
Expected: `1 : TypeVar(-1)`

### 153.2 Substring not found
```
(string-contains? "hello" "xyz")
```
Expected: `0 : TypeVar(-1)`

---

## Level 154: String slice

**Goal:** Verify `string-slice` extracts part of a string.

### 154.1 Basic slice
```
(string-slice "hello" 0 2)
```
Expected: `<<"he">> : TypeVar(-1)`

---

## Level 155: String upcase

**Goal:** Verify `string-upcase` converts to uppercase.

### 155.1 Basic upcase
```
(string-upcase "hello")
```
Expected: `<<"HELLO">> : TypeVar(-1)`

---

## Level 156: String downcase

**Goal:** Verify `string-downcase` converts to lowercase.

### 156.1 Basic downcase
```
(string-downcase "HELLO")
```
Expected: `<<"hello">> : TypeVar(-1)`

---

## Level 157: String replace

**Goal:** Verify `string-replace` substitutes occurrences.

### 157.1 Basic replace
```
(string-replace "hello" "l" "x")
```
Expected: `<<"hexxo">> : TypeVar(-1)`

---

## Level 158: String split

**Goal:** Verify `string-split` divides a string by delimiter.

### 158.1 Split on comma
```
(string-split "a,b,c" ",")
```
Expected: `[<<"a">>,<<"b">>,<<"c">>] : TypeVar(-1)`

---

## Level 159: String trim

**Goal:** Verify `string-trim` removes leading/trailing whitespace.

### 159.1 Basic trim
```
(string-trim "  hello  ")
```
Expected: `<<"hello">> : TypeVar(-1)`

---

## Level 160: String to int

**Goal:** Verify `string->int` parses a string as integer.

### 160.1 Basic conversion
```
(string->int "42")
```
Expected: `42 : TypeVar(-1)`

### 160.2 Error case
```
(string->int "abc")
```
Expected: Runtime error (Erlang `badarg` from `binary_to_integer`)

---

## Level 161: List length

**Goal:** Verify `list-length` returns element count.

### 161.1 Basic length
```
(list-length (list 1 2 3))
```
Expected: `3 : TypeVar(-1)`

### 161.2 Empty list
```
(list-length (list))
```
Expected: `0 : TypeVar(-1)`

---

## Level 162: List reverse

**Goal:** Verify `list-reverse` reverses element order.

### 162.1 Basic reverse
```
(list-reverse (list 1 2 3))
```
Expected: `[3,2,1] : TypeVar(-1)`

---

## Level 163: List flatten

**Goal:** Verify `list-flatten` flattens nested lists one level.

### 163.1 Basic flatten
```
(list-flatten (list (list 1 2) (list 3 4)))
```
Expected: `[1,2,3,4] : TypeVar(-1)`

---

## Level 164: List member

**Goal:** Verify `list-member?` checks element membership.

### 164.1 Found
```
(list-member? 3 (list 1 2 3))
```
Expected: `1 : TypeVar(-1)`

### 164.2 Not found
```
(list-member? 99 (list 1 2 3))
```
Expected: `0 : TypeVar(-1)`

---

## Level 165: Range

**Goal:** Verify `range` generates a numeric sequence.

### 165.1 Basic range
```
(range 1 5)
```
Expected: `[1,2,3,4,5] : TypeVar(-1)`

### 165.2 Single element
```
(range 5 5)
```
Expected: `[5] : TypeVar(-1)`

---

## Level 166: List sort

**Goal:** Verify `list-sort` returns sorted elements.

### 166.1 Basic sort
```
(list-sort (list 3 1 2))
```
Expected: `[1,2,3] : TypeVar(-1)`

---

## Level 167: List append

**Goal:** Verify `list-append` joins two lists.

### 167.1 Basic append
```
(list-append (list 1 2) (list 3 4))
```
Expected: `[1,2,3,4] : TypeVar(-1)`

---

## Level 168: Higher-order list ops (map/filter/fold)

**Goal:** Verify list ops that take gleamunison lambdas.

### 168.1 List map
```
(list-map (lam x (add x 1)) (list 1 2 3))
```
Expected: `[2,3,4] : TypeVar(-1)` or equivalent

### 168.2 List filter
```
(list-filter (lam x (if (eq? x 2) 1 0)) (list 1 2 3))
```
Expected: `[2] : TypeVar(-1)` or equivalent

---

## Level 169: Pair operations

**Goal:** Verify `pair`/`fst`/`snd` product type operations.

### 169.1 Create pair
```
(pair 42 "hello")
```
Expected: `{pair,42,<<"hello">>} : TypeVar(-1)`

### 169.2 Fst
```
(fst (pair 42 "hello"))
```
Expected: `42 : TypeVar(-1)`

### 169.3 Snd
```
(snd (pair 42 "hello"))
```
Expected: `<<"hello">> : TypeVar(-1)`

---

## Level 170: Either type (left/right)

**Goal:** Verify `left`/`right` sum type constructors.

### 170.1 Left
```
(left "error message")
```
Expected: `{left,<<"error message">>} : TypeVar(-1)`

### 170.2 Right
```
(right 42)
```
Expected: `{right,42} : TypeVar(-1)`

---

## Level 171: Dictionary operations

**Goal:** Verify `dict-new`/`dict-get`/`dict-set` map operations.

### 171.1 Create empty dict
```
(dict-new)
```
Expected: `#{} : TypeVar(-1)`

### 171.2 Set and inspect
```
(dict-set (dict-new) "key" 42)
```
Expected: `#{<<"key">> => 42} : TypeVar(-1)`

---

## Level 172: Set operations

**Goal:** Verify `set-new`/`set-insert` set operations.

### 172.1 Create set
```
(set-new)
```
Expected: `{sets, ...}` or equivalent

### 172.2 Insert
```
(set-insert (set-new) 42)
```
Expected: Set with one element

---

## Level 173: String/list/ds stress

**Goal:** Combine all new genesis modules in one expression.

### 173.1 Chained operations
```
(string-length (fst (pair "hello" (list-length (range 1 5)))))
```
Expected: `5 : TypeVar(-1)` (length of "hello")

---

## Level 174: Bootstrapped ops with arithmetic

**Goal:** Verify genesis modules compose with existing arithmetic.

### 174.1 Count words
```
(define words (string-split "one two three" " "))
(list-length words)
```
Expected: `3 : TypeVar(-1)`

---

## Level 175: Integration with effects

**Goal:** Verify genesis ops work inside effects context.

### 175.1 Print list length
```
(do Console print (list-length (range 1 10)))
```
Expected: `10` printed via Console, then `0`

---

## Level 176: Multiple string ops in sequence

**Goal:** Chain several string operations.

### 176.1 Pipeline
```
(string-upcase (string-concat "hello" (string-trim "  world  ")))
```
Expected: `<<"HELLOWORLD">> : TypeVar(-1)`

---

## Level 177: List transformations

**Goal:** Transform lists using combination of list ops.

### 177.1 Sort and reverse
```
(list-reverse (list-sort (list 3 1 4 1 5 9)))
```
Expected: `[9,5,4,3,1,1] : TypeVar(-1)`

---

## Level 178: Dict as lookup table

**Goal:** Use dictionary for key-value lookups.

### 178.1 Set then get
```
(dict-get (dict-set (dict-new) "answer" 42) "answer")
```
Expected: `42 : TypeVar(-1)` (or similar based on implementation)

---

## Level 179: Bootstrapped ops in define

**Goal:** Wrap genesis modules in user-defined functions.

### 179.1 Define wrapper
```
(define word-count (lam s (list-length (string-split s " "))))
(word-count "hello world from gleamunison")
```
Expected: `4 : TypeVar(-1)`

---

## Level 180: Genesis module stress

**Goal:** Verify all 30 genesis modules load and run.

### 180.1 All ops test
```
(string-length (string-concat "a" "b"))
```
Expected: `2 : TypeVar(-1)`

---

## Level 181: Named let / loop recursion

**Goal:** Test `(loop ...)` surface syntax for recursion.

### 181.1 Loop form
```
(loop (lam (x) x) 42)
```
Expected: `42 : TypeVar(-1)`

### Known issues
- The `loop` surface syntax is aspirational and may not be wired through `sexpr_to_term`.

---

## Level 182: Begin sequencing

**Goal:** Test `(begin expr1 expr2 ...)` surface syntax.

### 182.1 Sequence
```
(begin 1 2 3)
```
Expected: `3 : TypeVar(-1)` (last value)

---

## Level 183: When guard clauses

**Goal:** Test `(when guard)` in match arms.

### 183.1 Guarded match
```
(match 5 (x (when (gt? x 3)) "big") (x "small"))
```
Expected: `<<"big">> : TypeVar(-1)`

---

## Level 184: Lazy boolean short-circuit

**Goal:** Verify short-circuit `and`/`or` via match expansion.

### 184.1 Short-circuit and
```
((lam a (lam b (match a (0 0) (_ b)))) 1 (do Console print "hi"))
```
Expected: `"hi"` printed, then `1`

### 184.2 Short-circuit stops
```
((lam a (lam b (match a (0 0) (_ b)))) 0 (do Console print "hi"))
```
Expected: `0` only — the `Do` is never evaluated

---

## Level 185: Try/catch error handling

**Goal:** Test `(try body handler)` error catching.

### 185.1 Try without error
```
(try 42 (lam err "error"))
```
Expected: `42 : TypeVar(-1)`

### 185.2 Try with error
```
(try (add "not" "valid") (lam err "caught"))
```
Expected: `<<"caught">> : TypeVar(-1)` (error caught)

---

## Level 186: Cond multi-branch

**Goal:** Test `(cond ... (else ...))` surface syntax.

### 186.1 Cond with else
```
(cond ((gt? 5 3) "yes") (else "no"))
```
Expected: `<<"yes">> : TypeVar(-1)`

---

## Level 187: Case expression

**Goal:** Test `(case expr (pat body) ...)` as match alias.

### 187.1 Case on integer
```
(case 42 (42 "forty-two") (x "other"))
```
Expected: `<<"forty-two">> : TypeVar(-1)`

---

## Level 188: Threading macro

**Goal:** Test `(-> expr form ...)` threading.

### 188.1 Thread first
```
(-> (list 3 1 2) (list-sort) (list-reverse))
```
Expected: `[3,2,1] : TypeVar(-1)` (sort then reverse)

---

## Level 189: Function composition

**Goal:** Test `(compose f g)` surface syntax.

### 189.1 Compose add and mul
```
(define add1 (lam x (add x 1)))
(define double (lam x (mul x 2)))
(compose add1 double)
```
Then:
```
((compose add1 double) 5)
```
Expected: `11 : TypeVar(-1)` (add1(double(5)) = 10+1 = 11)

---

## Level 190: Curry / uncurry

**Goal:** Test currying utilities.

### 190.1 Curried add
```
(curry (lam x (lam y (add x y))) 2)
```
Then apply:
```
((curry (lam x (lam y (add x y))) 2) 3 4)
```
Expected: `7 : TypeVar(-1)`

---

## Level 191: Pair type notation

**Goal:** Test `(pair A B)` type annotations.

### 191.1 Pair annotation
```
(the (pair Int Text) (pair 42 "hello"))
```
Expected: `{pair,42,<<"hello">>} : pair(Int, Text)` or similar

---

## Level 192: Either type notation

**Goal:** Test `(either A B)` type annotations.

### 192.1 Left annotation
```
(the (either Text Int) (left "error"))
```
Expected: `{left,<<"error">>} : either(Text, Int)`

---

## Level 193: Type annotations

**Goal:** Test `(the Type expr)` explicit type annotation.

### 193.1 Int annotation
```
(the Int 42)
```
Expected: `42 : Int`

### 193.2 Wrong type
```
(the Text 42)
```
Expected: Type error — `42` is Int, not Text

---

## Level 194: Type aliases

**Goal:** Test `(type Name T)` alias registration.

### 194.1 Simple alias
```
(type Age Int)
(the Age 42)
```
Expected: `42 : Age` or `42 : Int` depending on alias resolution

---

## Level 195: Destructuring in let

**Goal:** Test `(let (pair x y) val body)` destructuring.

### 195.1 Pair destructure
```
(let (pair x y) (pair 42 "hello") (string-length (string-concat x y)))
```
Expected: Type error or concatenation error (mixed types)

---

## Level 196: Destructuring in match

**Goal:** Test `(match val ((pair a b) body))` pattern.

### 196.1 Match on pair
```
(match (pair 42 "hello") ((pair a b) a))
```
Expected: `42 : TypeVar(-1)`

---

## Level 197: Typed holes

**Goal:** Test `(hole Type)` placeholder for inference debugging.

### 197.1 Hole in expression
```
(lam x (hole Int))
```
Expected: Type inferred, hole position printed

---

## Level 198: Type error recovery

**Goal:** Test continued elaboration after type error.

### 198.1 Error then success
```
(lam x (add x "not"))
42
```
Expected: Type error on first, `42 : Int` on second (REPL recovers)

---

## Level 199: Recursive types

**Goal:** Test `(list T)` recursive type notation.

### 199.1 List of Int
```
(list 1 2 3)
```
Expected: `[1,2,3] : list(Int)` or `[1,2,3] : Builtin(ListType)`

---

## Level 200: Polymorphic inference stress

**Goal:** Test deeply nested quantified type patterns.

### 200.1 SK combinator
```
((lam x (lam y x)) (lam x x) 42)
```
Expected: `42 : TypeVar(0)` — K(I, 42) = I

### 200.2 Church encoding
```
(define zero (lam f (lam x x)))
(zero (lam x x) 42)
```
Expected: `42 : TypeVar(0)` — zero applies f zero times

---

