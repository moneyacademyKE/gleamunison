## Level 401: Rank-1 polymorphism
**Goal:** Identity at Int and Text.
### 401.1 Test
```
((lam x x) 42) and ("hello")
```
Expected: Both typecheck

---

## Level 402: Recursive types
**Goal:** List type definition.
### 402.1 Test
```
(type List a (Nil) (Cons a (List a)))
```
Expected: Type defined

---

## Level 403: Type variable scope
**Goal:** Deeply nested.
### 403.1 Test
```
(lam a (lam b (lam c (lam d a))))
```
Expected: Typed as Fn chain

---

## Level 404: Let generalization
**Goal:** Monomorphic restriction.
### 404.1 Test
```
(define id (lam x x)) ((id 42) (id "hi"))
```
Expected: Error or TVar(-1)

---

## Level 405: Type annotations
**Goal:** Correct/wrong types.
### 405.1 Test
```
(the Int 42) vs (the Text 42)
```
Expected: Pass / Error

---

## Level 406: Row polymorphism
**Goal:** Open record tails.
### 406.1 Test
```
(the {name: Text, age: Int} {name: "A", age: 30})
```
Expected: Record typed

---

## Level 407: Subsumption
**Goal:** Wider context.
### 407.1 Test
```
(lam x (pair x x)) at Int and Text
```
Expected: Widens correctly

---

## Level 408: Occurs check
**Goal:** Self-application fails.
### 408.1 Test
```
(lam x (x x))
```
Expected: Infinite type error

---

## Level 409: Mutual types
**Goal:** A refs B refs A.
### 409.1 Test
```
(type A (A_con B)) (type B (B_con A))
```
Expected: Types defined

---

## Level 410: Perf: 100 nested
**Goal:** Inference in < 500ms.
### 410.1 Test
```
(lam a0 ... (lam a99 a99)...)
```
Expected: < 500ms

---

## Level 411: Cross-expression define
**Goal:** Define then use.
### 411.1 Test
```
(define f (lam x (add x 1))) (f 41)
```
Expected: 42

---

## Level 412: Hash collision
**Goal:** Same hash overwrites.
### 412.1 Test
```
(define a 42) (define b 42)
```
Expected: Both define OK

---

## Level 413: Dependency ordering
**Goal:** B before A.
### 413.1 Test
```
(define dbl (lam x (add x x))) (define quad ...) (quad 2)
```
Expected: 8

---

## Level 414: Circular dep detection
**Goal:** A→B→A error.
### 414.1 Test
```
(define a b) (define b a)
```
Expected: Circular dep error

---

## Level 415: Module exports
**Goal:** List exported fns.
### 415.1 Test
```
(exports-of m_00000001)
```
Expected: ["$eval"]

---

## Level 416: Reload cycle
**Goal:** Define→eval→redefine→eval.
### 416.1 Test
```
(define x 1) x (define x 2) x
```
Expected: 1 then 2

---

## Level 417: Purge confirmation
**Goal:** delete+purge clears.
### 417.1 Test
```
code:delete + code:purge
```
Expected: Module removed

---

## Level 418: Cross-module types
**Goal:** Type across defs.
### 418.1 Test
```
(define p1 (pair 1 2)) (define p2 (pair 3 4)) (fst p1)
```
Expected: 1

---

## Level 419: Atom cleanup
**Goal:** No orphan atoms after purge.
### 419.1 Test
```
:atoms before/after define/purge
```
Expected: Returns to baseline

---

## Level 420: 100-module chain
**Goal:** Linear dep chain.
### 420.1 Test
```
v99 ... v0 chain
```
Expected: All resolve

---

## Level 421: Variable pattern
**Goal:** Var used as pattern.
### 421.1 Test
```
(let x 42 (match x (x "matched")))
```
Expected: "matched"

---

## Level 422: Wildcard
**Goal:** Catches all.
### 422.1 Test
```
(match 42 (_ "any"))
```
Expected: "any"

---

## Level 423: Text pattern
**Goal:** Match on string.
### 423.1 Test
```
(match "hi" ("hi" "m") (x "n"))
```
Expected: "m"

---

## Level 424: Nested pattern
**Goal:** Pair destructuring.
### 424.1 Test
```
(match (pair 1 2) ((pair x y) (add x y)))
```
Expected: 3

---

## Level 425: Multi-case
**Goal:** 10 arms.
### 425.1 Test
```
(match 5 (1 "a") ... (5 "e") (x "other"))
```
Expected: "e"

---

## Level 426: Or-pattern
**Goal:** Match 1 or 2.
### 426.1 Test
```
(match 1 ((1 2) "a") (x "b")) (match 2 ...)
```
Expected: "a" for both

---

## Level 427: As-pattern
**Goal:** Bind whole value.
### 427.1 Test
```
(match (pair 1 2) ((pair x _) as p (fst p)))
```
Expected: 1

---

## Level 428: Pattern with effect
**Goal:** Do in match arm.
### 428.1 Test
```
(match 1 (1 (do Console print "one")) (x "other"))
```
Expected: "one" printed

---

## Level 429: Exhaustiveness
**Goal:** Incomplete match warns.
### 429.1 Test
```
(match 1 (2 "two"))
```
Expected: Exhaustiveness warning

---

## Level 430: Redundant pattern
**Goal:** Unreachable arm flagged.
### 430.1 Test
```
(match 1 (x "a") (y "b"))
```
Expected: Redundancy warning

---

## Level 431: Serialization round-trip
**Goal:** Term→bytes→Term.
### 431.1 Test
```
(serialize-def x) (deserialize bytes)
```
Expected: Round-trip preserved

---

## Level 432: Hash stability
**Goal:** Same def → same hash.
### 432.1 Test
```
(define x 42) (define y 42)
```
Expected: Same hash

---

## Level 433: Codebase listing
**Goal:** List all defs.
### 433.1 Test
```
:defs
```
Expected: All user defs listed

---

## Level 434: Query by type
**Goal:** Filter TermDefs.
### 434.1 Test
```
:term-defs
```
Expected: Only term defs

---

## Level 435: Codebase size
**Goal:** Def count.
### 435.1 Test
```
:def-count
```
Expected: Integer count

---

## Level 436: Dependency tree
**Goal:** RefTo walk.
### 436.1 Test
```
(deps-of quadruple)
```
Expected: ["add","double"]

---

## Level 437: Codebase diff
**Goal:** Compare two CBs.
### 437.1 Test
```
(codebase-diff cb1 cb2)
```
Expected: {new, missing, changed}

---

## Level 438: Codebase merge
**Goal:** Combine + dedup.
### 438.1 Test
```
(merge cb1 cb2)
```
Expected: Combined

---

## Level 439: GC mark
**Goal:** Walk reachable.
### 439.1 Test
```
(gc-mark)
```
Expected: Reachable refs set

---

## Level 440: GC sweep
**Goal:** Remove unreachable.
### 440.1 Test
```
(gc-sweep)
```
Expected: Reachable survive

---

## Level 441: Source context
**Goal:** Pointer to error.
### 441.1 Test
```
(let x 5
```
Expected: Line+col+pointer

---

## Level 442: Name suggestions
**Goal:** "Did you mean add?".
### 442.1 Test
```
(ad 1 2)
```
Expected: NameNotFound with suggestion

---

## Level 443: Type error location
**Goal:** Which expression failed.
### 443.1 Test
```
(add 1 "hello")
```
Expected: Located at arg 2

---

## Level 444: Runtime stack trace
**Goal:** Which def + line.
### 444.1 Test
```
(define crash (lam x (add x "bad"))) (crash 1)
```
Expected: Trace with def names

---

## Level 445: Unused warning
**Goal:** Binding not used.
### 445.1 Test
```
(let x 1 42)
```
Expected: Warning: x unused

---

## Level 446: Shadow warning
**Goal:** Inner shadows outer.
### 446.1 Test
```
(let x 1 (let x 2 x))
```
Expected: Shadow warning

---

## Level 447: Error count
**Goal:** Session error log.
### 447.1 Test
```
:errors
```
Expected: Errors with timestamps

---

## Level 448: Warning count
**Goal:** Session warning log.
### 448.1 Test
```
:warnings
```
Expected: Warnings with timestamps

---

## Level 449: Severity levels
**Goal:** Parse > Type > Runtime.
### 449.1 Test
```
:errors --severity=error
```
Expected: Filtered by severity

---

## Level 450: JSON errors
**Goal:** Tool-friendly format.
### 450.1 Test
```
:errors --format=json
```
Expected: JSON error array

---

| # | Name | Type | Primitives Needed | Status |
|---|---|---|---|---|
| 101 | `sub`/`mul` arithmetic | Genesis | `m_0000000b`/`m_0000000c` genesis modules | ✓ Done |
| 102 | `div`/`mod` integer ops | Genesis | `m_0000000d`/`m_0000000e` genesis modules | ✓ Done |
| 103 | `eq?`/`lt?`/`gt?` comparison | Genesis | Boolean genesis modules | ✓ Done |
| 104 | `and`/`or`/`not` boolean ops | Genesis | Boolean logic genesis modules | ✓ Done |
| 105 | `if` conditional special form | Parser | Conditional expression syntax | ✓ Done |
| 106 | String concatenation | Genesis | `string-concat` bootstrap | Planned |
| 107 | String predicates | Genesis | `contains?`, `starts-with?`, `ends-with?` | Planned |
| 108 | String manipulation | Genesis | `replace`, `split`, `join` | Planned |
| 109 | String transforms | Genesis | `slice`, `length`, `upcase`, `downcase` | Planned |
| 110 | String↔Int/Float conversion | Genesis | `string->int`, `int->string`, `string->float` | Planned |
| 111 | List operations: length/reverse | Genesis | Bootstrapped list primitives | Planned |
| 112 | List: map/filter/fold | Genesis | Higher-order list operations | Planned |
| 113 | List: append/flatten/zip | Genesis | List combination operations | Planned |
| 114 | List: sort/find/member? | Genesis | List search and ordering | Planned |
| 115 | `range` numeric list generator | Genesis | `(range 0 10)` → list 0..10 | Planned |
| 116 | Product types (pairs/tuples) | Type System | `(pair 1 2)`, `(fst p)`, `(snd p)` | Planned |
| 117 | Sum types (Either/Option) | Type System | `(left "err")` / `(right 42)` | Planned |
| 118 | Type annotations | Type System | `(the Int 42)` explicit typing | Planned |
| 119 | Type aliases | Type System | `(type Age Int)` syntax | Planned |
| 120 | Destructuring in let/match | Parser | Pattern bindings for pairs/lists | Planned |
| 121 | Named let / loop recursion | Parser | `(loop (lam (x) ...) init)` | Planned |
| 122 | `begin` sequencing | Parser | `(begin expr1 expr2 ... exprn)` | Planned |
| 123 | `when` guard clauses | Parser | `(match x (p (when g) body))` | Planned |
| 124 | Lazy boolean operators | Parser | Short-circuit `and`/`or` | Planned |
| 125 | Try/catch error handling | Parser | `(try body (lam err handler))` | Planned |
| 126 | Codebase integrity check | Storage | Hash verification for all defs | Planned |
| 127 | Codebase repair | Storage | Rehash and fix corrupt entries | Planned |
| 128 | Storage adapter benchmarks | Storage | ETS vs DETS vs partitioned throughput | Planned |
| 129 | Large codebase stress (100K) | Storage | Memory and time with 100K definitions | Planned |
| 130 | Concurrent codebase access | Storage | Multi-REPL shared DETS access | Planned |
| 131 | REPL history | REPL | Arrow-key navigation | Planned |
| 132 | REPL meta-commands | REPL | `:help`, `:env`, `:defs`, `:gc` | Planned |
| 133 | Expression inspector | REPL | `(inspect expr)` → AST + type | Planned |
| 134 | Trace mode | REPL | `:trace expr` step-by-step | Planned |
| 135 | Profile mode | REPL | `:profile expr` time breakdown | Planned |
| 136 | WebSocket endpoint | Web | HTTP→WebSocket upgrade | Planned |
| 137 | SSE streaming endpoint | Web | Server-Sent Events push | Planned |
| 138 | Static file serving | Web | `GET /files/*` directory serving | Planned |
| 139 | Middleware pipeline | Web | Request pre/post processing | Planned |
| 140 | Web-based REPL console | Web | Browser REPL via WebSocket | Planned |
| 141 | Todo app v2 persistent | App | DETS-backed, categories, search | Planned |
| 142 | Chat server | App | WebSocket, broadcast, rooms | Planned |
| 143 | URL shortener | App | HTTP redirect, persistent storage | Planned |
| 144 | Key-value store server | App | Full CRUD, REST API | Planned |
| 145 | Static site generator | App | Markdown files → HTML output | Planned |
| 146 | S-expression parser in gleamunison | Meta | Parse surface syntax from within | Planned |
| 147 | Compiler self-test | Meta | Compile AST, load, verify results | Planned |
| 148 | Bootstrapped version info | Meta | `(gleamunison-version)` metadata | Planned |
| 149 | Full-stack app with auth | App | Sessions, login, logout | Planned |
| 150 | Meta-benchmark runner | Meta | All 150 levels pass/fail/time | Planned |
| 151–160 | String ops (10 modules) | Genesis | concat, length, contains, slice, upcase, replace, split, trim, int→str | ✓ Done |
| 161–170 | List ops (10 modules) | Genesis | length, reverse, map, filter, fold, append, zip, sort, find, range | ✓ Done |
| 171–180 | Data structures (10 modules) | Genesis | pair, fst/snd, left/right (Either), dict, set | ✓ Done |
| 181–190 | Control flow (10 forms) | Parser | loop, begin, when, lazy and/or, try/catch, cond, case, thread, compose, curry | Planned |
| 191–200 | Type extensions (10 features) | Type | pair types, sum types, annotations, aliases, destruct, holes, recovery, recursive, poly stress | Planned |
| 201–210 | Storage depth (10 ops) | Storage | integrity, repair, benchmark, 100K stress, concurrent, snapshot, restore, GC, migrate, diff | Planned |
| 211–220 | REPL tooling (10 features) | REPL | history, meta-cmd, inspect, trace, profile, editing, tab-complete, color, errors, script-load | Planned |
| 221–230 | Web extensions (10 features) | Web | WebSocket, SSE, static files, middleware, web REPL, routing, JSON, CORS, rate-limit, logging | Planned |
| 231–240 | Apps Part 1 (10 apps) | App | todo v2, chat, URL shortener, KV store, site gen, blog, pastebin, polls, guestbook, uploads | Planned |
| 241–250 | Apps Part 2 (10 systems) | App | validation, templating, routing, sessions, auth, migrations, jobs, webhooks, admin, gateway | Planned |
| 251–260 | Self-hosting (10 tools) | Meta | sexpr parser, pretty-printer, code gen, compiler test, version, test runner, coverage, docs, formatter, analysis | Planned |
| 261–270 | Benchmarking (10 metrics) | Perf | microbench, compile time, runtime, memory, atom table, process count, 1M defs, ops/sec, web throughput, connections | Planned |
| 271–280 | Distributed (10 protocols) | Net | discovery, remote spawn, remote send, sync, distributed KV, membership, failure, leader, counter, pub/sub | Planned |
| 281–290 | Effects complete (10 patterns) | Effects | Math ability, Show, stateful, composition, forwarding, abort, choice, reader, writer, state effect | Planned |
| 291–300 | Security (10 patterns) | Sec | validation, rate-limit, CORS, CSRF, sessions, hashing, tokens, RBAC, audit, scan | Planned |
| 301–310 | Tooling (10 systems) | Tool | source maps, multi-file, modules, packages, cache, watch, LSP, highlighting, diagnostics, actions | Planned |
| 311–320 | Math & data (10 modules) | Math | basic math, trig, random, stats, matrices, vectors, distances, normalize, regression, kNN | Planned |
| 321–330 | Protocols (10 modules) | Net | TCP echo, UDP, DNS, ping, HTTP/2, TLS, file watch, signals, env, CLI args | Planned |
| 331–340 | Encoding (10 modules) | Format | datetime, UUID, base64, hex, CRC, compress, serialize, JSON gen, CSV, INI | Planned |
| 341–350 | Grand finale (10 apps) | App | markdown renderer, JSON parser, HTTP client, script runner, debugger, self-test, notes app, collab editor, API gateway, package server v2 | Planned |
| 351–360 | Effects integration (10 features) | Effects | Custom ability, multi-op handler, forwarding, composition, abort, state, reader, writer, choice, error effect | Planned |
| 361–370 | Error handling (10 features) | Error | Parse error recovery, name error recovery, type error recovery, runtime try/catch, sequential errors, line/col accuracy, message clarity, crash recovery, handler crash | Planned |
| 371–380 | Memory & resources (10 features) | Perf | Atom table baseline/growth, process count, codebase memory, loader count, purge success, leak detection, binary cleanup | Planned |
| 381–390 | Parser hardening (10 features) | Parser | Deep nesting, long identifiers, large ints, empty program, comment everywhere, escaped quotes, unicode ids, tabs/spaces, perf, tokenizer perf | Planned |
| 391–400 | Compiler optimization (10 features) | Compile | Constant folding, dead let elim, inline lambda, match simplify, let chaining, apply flatten, ref direct call, dead branch, compile perf, beam size | Planned |
| 401–410 | Type inference depth (10 features) | Type | Rank-1 poly, recursive type, type var scope, let generalization, annotation check, row poly, subsumption, occurs check, mutual types, perf | Planned |
| 411–420 | Module system (10 features) | Module | Cross-expression define, name collision, dep ordering, circular dep, export listing, reload cycle, purge confirm, cross-module types, atom cleanup, chain | Planned |
| 421–430 | Pattern matching (10 features) | Parser | Var reuse, wildcard, text pattern, nested pattern, multi-case, or-pattern, as-pattern, pattern+effect, exhaustiveness, redundant pattern | Planned |
| 431–440 | Codebase & serialization (10 features) | Storage | Serialization round-trip, hash stability, codebase list, query by type, size count, dep tree, diff, merge, GC mark, GC sweep | Planned |
| 441–450 | Error quality (10 features) | Error | Source context, name suggestions, type error location, runtime stack trace, unused warning, shadow warning, error count, warning count, severity, structured output | Planned |
| 451–460 | Developer tools (10 features) | Tool | REPL history, pretty-printer, tab completion, multi-line editor, color output, script loading, batch eval, timing, welcome banner, meta-commands | Planned |
| 461–470 | Scripting (10 features) | Script | File read FFI, file write FFI, script args, exit code, multi-file eval, shebang, env vars, command exec, pipeline, library import | Planned |
| 471–480 | System integration (10 features) | Sys | File listing, deletion, directory creation, file info, file exists, temp files, pwd, cd, process list, system info | Planned |
| 481–490 | Numerical computing (10 features) | Math | abs, negate, min/max, floor/ceil, sqrt, random-int, random-float, mean/median, sum/product, variance/stdev | Planned |
| 491–500 | Data transformation (10 features) | Data | Int→float, float→int, bytes→hex, hex→bytes, str→bytes, list→str, str→list, type coercion, JSON gen, CSV parse | Planned |
| 501–510 | Effects expansion (10 features) | Effects | Math ability, Logger ability, Config ability, Clock ability, stack nesting, composition, handler chain, aliasing, default handlers, routing | Planned |
| 511–520 | Web applications (10 features) | Web | JSON API, form parsing, cookies, sessions, static files, route params, query params, POST body, response headers, status codes | Planned |
| 521–530 | Database & storage (10 features) | Storage | DETS recovery, integrity, repair, backup, restore, KV store, typed KV, TTL, key listing, batch ops | Planned |
| 531–540 | Concurrency (10 features) | Conc | Spawn with args, spawn+wait, spawn many, send to self, registry, timeout recv, selective recv, linking, link propagation, monitoring | Planned |
| 541–550 | Testing (10 features) | Test | Assertion, test runner, test grouping, fixtures, coverage, property-based, fuzz, benchmark, comparison, test report | Planned |
| 551–560 | Data structures (10 features) | DS | Option, Result, Either, linked list, binary tree, queue, stack, priority queue, graph, trie | Planned |
| 561–570 | Combinators (10 features) | Func | Compose, pipe, curry, uncurry, const, flip, apply, iterate, fix | Planned |
| 571–580 | Error stress (10 features) | Stress | 1000 empty evals, symbol errors, mixed 10K ops, max atom, max binary, max list, max recursion, dict pollution, codebase overflow, OOM detection | Planned |
| 581–590 | Benchmarks (10 features) | Perf | Tokenizer, parser, elaboration, type-check, compile, load, eval, codebase insert, pipeline, steady-state | Planned |
| 591–600 | Release (10 features) | Rel | Escript all-deps, custom header, size opt, embedded HTML, OTP compat, macOS, Linux, Windows, CI, release script | Planned |
| 601–700 | Systems (100 features) | Sys | Caching, logging, config, monitoring, profiling, tracing, debugging, error handling, resilience, security | Planned |
| 701–800 | Language & Compiler (100 features) | Compile | Type inference, pattern extensions, control flow, module system, code gen, error messages, REPL features, FFI, effects system, serialization | Planned |
| 801–900 | Applications (100 features) | App | Web framework, HTTP client, data processing, database, networking, concurrency, file IO, system, math, testing | Planned |
| 901–1000 | Platform (100 features) | Plat | Todo app, chat app, blog engine, site generator, package server, dashboard, script runner, meta-tester, self-hosted REPL, platform finale | Planned |

---

## Level 451: REPL history
**Goal:** Arrow keys recall previous expressions.
### 451.1 Test
```
42, then press Up
```
Expected: 42 recalled

---

## Level 452: Pretty-printer
**Goal:** Formatted S-expression output.
### 452.1 Test
```
(pretty-print (define x 42))
```
Expected: Formatted output

---

## Level 453: Tab completion
**Goal:** Complete names from bootstrap.
### 453.1 Test
```
st + Tab
```
Expected: string-concat, string-length...

---

## Level 454: Multi-line editor
**Goal:** Cursor movement across lines.
### 454.1 Test
```
multi-line input with cursor
```
Expected: Edits correctly

---

## Level 455: Color output
**Goal:** ANSI syntax highlighting.
### 455.1 Test
```
42
```
Expected: 42 in yellow, type in green

---

## Level 456: Script loading
**Goal:** (load "file.gleam").
### 456.1 Test
```
(load "test.gleam")
```
Expected: 42 : Builtin(IntType)

---

## Level 457: Batch eval
**Goal:** Echo | escript processes stdin.
### 457.1 Test
```
echo 42 | escript
```
Expected: 42 : Builtin(IntType)

---

## Level 458: Expression timing
**Goal:** ms per eval.
### 458.1 Test
```
42
```
Expected: Shows elapsed time

---

## Level 459: Welcome banner
**Goal:** Version and help hint at startup.
### 459.1 Test
```
start REPL
```
Expected: Banner with version, ops, help

---

## Level 460: Meta-commands
**Goal:** :help, :env, :defs, :gc, :version.
### 460.1 Test
```
:help
```
Expected: Available commands listed

---

## Level 461: File read FFI
**Goal:** Read file contents.
### 461.1 Test
```
(file-read "test.txt")
```
Expected: File contents

---

## Level 462: File write FFI
**Goal:** Write to file.
### 462.1 Test
```
(file-write "out.txt" "content")
```
Expected: Written

---

## Level 463: Script with args
**Goal:** escript passes arguments.
### 463.1 Test
```
escript run.gleam arg1 arg2
```
Expected: Args accessible

---

## Level 464: Exit code
**Goal:** Non-zero on error.
### 464.1 Test
```
escript err.gleam; echo $?
```
Expected: Exit code 1

---

## Level 465: Multi-file eval
**Goal:** Run multiple files.
### 465.1 Test
```
escript a.gleam b.gleam
```
Expected: Both evaluated

---

## Level 466: Shebang support
**Goal:** #!/usr/bin/env escript.
### 466.1 Test
```
./script.gleam direct
```
Expected: Runs correctly

---

## Level 467: Environment variables
**Goal:** os:getenv access.
### 467.1 Test
```
(getenv "PATH")
```
Expected: Path string

---

## Level 468: Shell command
**Goal:** Run external command.
### 468.1 Test
```
(shell "ls -la")
```
Expected: Command output

---

## Level 469: Pipeline
**Goal:** Read-process-write chain.
### 469.1 Test
```
(pipe (read "in") (proc) (write "out"))
```
Expected: Output written

---

## Level 470: Library import
**Goal:** (import "lib/utils.gleam").
### 470.1 Test
```
(import "utils.gleam")
```
Expected: Definitions available

---

## Level 471: File listing
**Goal:** List directory contents.
### 471.1 Test
```
(list-dir "/tmp")
```
Expected: File list

---

## Level 472: File deletion
**Goal:** Remove file.
### 472.1 Test
```
(file-delete "tmp.txt")
```
Expected: Success

---

## Level 473: Directory creation
**Goal:** mkdir.
### 473.1 Test
```
(make-dir "newdir")
```
Expected: Created

---

## Level 474: File info
**Goal:** Size, modified time.
### 474.1 Test
```
(file-info "test.txt")
```
Expected: Info map

---

## Level 475: File existence
**Goal:** Check exists.
### 475.1 Test
```
(file-exists? "test.txt")
```
Expected: 1 for found, 0 for missing

---

## Level 476: Temp files
**Goal:** Unique temp path.
### 476.1 Test
```
(temp-file)
```
Expected: Path string

---

## Level 477: Current directory
**Goal:** Working dir.
### 477.1 Test
```
(pwd)
```
Expected: Path string

---

## Level 478: Change directory
**Goal:** cd.
### 478.1 Test
```
(cd "/tmp")
```
Expected: Changed

---

## Level 479: Process list
**Goal:** Gleamunison processes.
### 479.1 Test
```
(ps)
```
Expected: Process list

---

## Level 480: System info
**Goal:** OS, CPU, memory.
### 480.1 Test
```
(sys-info)
```
Expected: Info map

---

## Level 481: Abs
**Goal:** Absolute value.
### 481.1 Test
```
(abs -5)
```
Expected: 5

---

## Level 482: Negate
**Goal:** Numeric negation.
### 482.1 Test
```
(negate 42)
```
Expected: -42

---

## Level 483: Min / Max
**Goal:** Comparison.
### 483.1 Test
```
(min 3 7) (max 3 7)
```
Expected: 3, 7

---

## Level 484: Floor / Ceil
**Goal:** Float rounding.
### 484.1 Test
```
(floor 3.14) (ceil 3.14)
```
Expected: 3, 4

---

## Level 485: Sqrt
**Goal:** Square root.
### 485.1 Test
```
(sqrt 9)
```
Expected: 3.0

---

## Level 486: Random int
**Goal:** Random in range.
### 486.1 Test
```
(random-int 1 100)
```
Expected: 1-100

---

## Level 487: Random float
**Goal:** 0.0 to 1.0.
### 487.1 Test
```
(random-float)
```
Expected: 0.0-1.0

---

## Level 488: Mean / Median
**Goal:** List stats.
### 488.1 Test
```
(mean [1 2 3 4 5])
```
Expected: 3.0

---

## Level 489: Sum / Product
**Goal:** List aggregation.
### 489.1 Test
```
(sum [1 2 3]) (product [1 2 3])
```
Expected: 6, 6

---

## Level 490: Variance / Stdev
**Goal:** Dispersion.
### 490.1 Test
```
(variance [1 2 3 4 5]) (stdev ...)
```
Expected: 2.5, ~1.58

---

## Level 491: Int to float
**Goal:** Conversion.
### 491.1 Test
```
(int->float 42)
```
Expected: 42.0

---

## Level 492: Float to int
**Goal:** Truncation.
### 492.1 Test
```
(float->int 3.14)
```
Expected: 3

---

## Level 493: Binary to hex
**Goal:** Encode.
### 493.1 Test
```
(bytes->hex <<"ABC">>)
```
Expected: 414243

---

## Level 494: Hex to binary
**Goal:** Decode.
### 494.1 Test
```
(hex->bytes "414243")
```
Expected: <<"ABC">>

---

## Level 495: String to binary
**Goal:** UTF-8 bytes.
### 495.1 Test
```
(str->bytes "text")
```
Expected: <<116,101,120,116>>

---

## Level 496: List to string
**Goal:** Join elements.
### 496.1 Test
```
(list->str [65 66 67])
```
Expected: "ABC"

---

## Level 497: String to list
**Goal:** Code points.
### 497.1 Test
```
(str->list "ABC")
```
Expected: [65,66,67]

---

## Level 498: Type coercion
**Goal:** The Type expr.
### 498.1 Test
```
(the Int 3.14)
```
Expected: 3

---

## Level 499: JSON generation
**Goal:** Term to JSON.
### 499.1 Test
```
(to-json [1 2 3])
```
Expected: "[1,2,3]"

---

## Level 500: CSV parsing
**Goal:** Row parsing.
### 500.1 Test
```
(parse-csv "a,b\n1,2")
```
Expected: [["a","b"],["1","2"]]

---

