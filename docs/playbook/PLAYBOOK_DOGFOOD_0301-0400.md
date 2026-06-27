## Level 301: Source maps

**Goal:** Error positions map to source locations.

### 301.1 Error with source
Type an expression with a type error:
```
(add 1 "hello")
```
Expected: Error includes source line and column: `Error at line 1, col 7`

---

## Level 302: Multi-file support

**Goal:** `(import "module.gleam")` loads definitions from another file.

### 302.1 Import
Create `lib.gleam` with `(define answer 42)`. Then:
```
(import "lib.gleam")
answer
```
Expected: `42 : Builtin(IntType)`

---

## Level 303: Module system

**Goal:** Namespaced definitions with qualified names.

### 303.1 Qualified reference
```
math.add
```
Where `math` module defines `add`.
Expected: `2` for `(math.add 1 1)`.

---

## Level 304: Package resolution

**Goal:** Search path for imports.

### 304.1 Search path
```
:import-path
```
Expected: `[".", "./lib", "./packages/*/src"]`

---

## Level 305: Build cache

**Goal:** Skip recompilation of unchanged definitions.

### 305.1 Cache hit
Define `(define x 42)` twice. Second define uses cached BEAM.
Expected: Second define completes in < 100 μs (cached).

---

## Level 306: Watch mode

**Goal:** File watcher auto-reloads on change.

### 306.1 Auto-reload
Start `gleam run -- watch`. Edit a source file.
Expected: File changes trigger recompile and reload.

---

## Level 307: LSP basics

**Goal:** `textDocument/completion` and `textDocument/hover` support.

### 307.1 Completions
Send LSP completion request for `st`:
Expected: `["string-concat", "string-length", "string-contains?"]`

---

## Level 308: Syntax highlighting

**Goal:** Token-based colorization.

### 308.1 Highlight
```
(highlight "(add 1 2)")
```
Expected: ANSI-colorized tokens: `(` in white, `add` in blue, `1` in yellow, etc.

---

## Level 309: Diagnostics

**Goal:** List all errors/warnings in the session.

### 309.1 Diagnostics
```
:diagnostics
```
Expected: `[{"severity": "error", "msg": "NameNotFound(\"bad\")", "at": "eval #42"}]`

---

## Level 310: Code actions

**Goal:** Quick-fix suggestions for common errors.

### 310.1 Fix typo
Type `(ad 1 2)`. Expected error with suggestion:
```
NameNotFound("ad"). Did you mean "add"?
```

---

## Level 311: Basic math ops

**Goal:** `abs`, `negate`, `sign`, `min`, `max`.

### 311.1 Abs
```
(abs -5)
```
Expected: `5`

### 311.2 Min
```
(min 3 7)
```
Expected: `3`

---

## Level 312: Trig functions

**Goal:** `sin`, `cos`, `tan`, `asin`, `acos`, `atan` via Erlang `math`.

### 312.1 Sin
```
(sin 0)
```
Expected: `0.0`

---

## Level 313: Random numbers

**Goal:** `random`, `random-int`, `random-float` via `rand` module.

### 313.1 Random int
```
(random-int 1 100)
```
Expected: Integer between 1 and 100 (inclusive).

---

## Level 314: Statistics

**Goal:** `mean`, `median`, `stdev`, `variance`.

### 314.1 Mean
```
(mean (list 1 2 3 4 5))
```
Expected: `3.0`

---

## Level 315: Matrix operations

**Goal:** Matrix addition, multiplication, transpose.

### 315.1 Matrix add
```
(matrix-add [[1 2] [3 4]] [[5 6] [7 8]])
```
Expected: `[[6 8] [10 12]]`

---

## Level 316: Vector operations

**Goal:** Vector addition, dot product, scaling.

### 316.1 Dot product
```
(vec-dot [1 2 3] [4 5 6])
```
Expected: `32` (1*4 + 2*5 + 3*6)

---

## Level 317: Distance metrics

**Goal:** Euclidean, Manhattan, cosine similarity.

### 317.1 Euclidean distance
```
(euclidean-dist [0 0] [3 4])
```
Expected: `5.0`

---

## Level 318: Data normalization

**Goal:** Normalize, standardize, min-max scale.

### 318.1 Min-max scale
```
(min-max-scale [1 2 3 4 5] 0 1)
```
Expected: `[0.0, 0.25, 0.5, 0.75, 1.0]`

---

## Level 319: Linear regression

**Goal:** Simple OLS regression.

### 319.1 Fit line
```
(linear-regression [[1 2] [2 4] [3 6]])
```
Expected: `{"slope": 2.0, "intercept": 0.0}`

---

## Level 320: k-NN classifier

**Goal:** k-nearest-neighbors classifier.

### 320.1 Classify
```
(knn-classify [1 2] [[[0 0] "A"] [[3 4] "B"] [[1 1] "A"]] 3)
```
Expected: `"A"` (majority of 3 nearest neighbors)

---

## Level 321: TCP echo server

**Goal:** `gen_tcp` accept → echo → close.

### 321.1 Echo
Connect to TCP port 9000, send `"hello"`:
Expected: Server echoes back `"hello"` and closes.

---

## Level 322: UDP listener

**Goal:** `gen_udp` open → receive → respond.

### 322.1 UDP ping
Send UDP datagram to port 9001 with `"ping"`:
Expected: Server responds with `"pong"`.

---

## Level 323: DNS resolution

**Goal:** `inet_res:gethostbyname/1`.

### 323.1 Resolve
```
(dns-resolve "example.com")
```
Expected: `{"host": "example.com", "addr": "93.184.216.34"}`

---

## Level 324: ICMP ping

**Goal:** Echo request via `gen_icmp`.

### 324.1 Ping host
```
(ping "localhost")
```
Expected: `{"host": "localhost", "rtt": 0.05}` (ms)

---

## Level 325: HTTP/2 basics

**Goal:** Minimal HTTP/2 framing.

### 325.1 HTTP/2 settings
Connect with HTTP/2 preface.
Expected: Server responds with SETTINGS frame.

---

## Level 326: TLS

**Goal:** `ssl:connect/3` for HTTPS client.

### 326.1 HTTPS get
```
(https-get "https://example.com")
```
Expected: Response body and status code.

---

## Level 327: File watcher

**Goal:** Poll `file:read_link_info/1` for changes.

### 327.1 Watch file
Start watching `test.txt`. Modify the file.
Expected: Watcher detects the change and reports it.

---

## Level 328: Signal handling

**Goal:** Handle SIGINT for graceful shutdown.

### 328.1 Ctrl-C
Press Ctrl-C while REPL is running.
Expected: `"SIGINT received. Type 'exit' to quit or continue."`

---

## Level 329: Environment variables

**Goal:** `os:getenv/1` for configuration.

### 329.1 Get PATH
```
(getenv "PATH")
```
Expected: String containing directory paths separated by `:`.

---

## Level 330: CLI argument parsing

**Goal:** Parse command-line arguments.

### 330.1 Simple CLI
```
./gleamunison_escript eval "42"
```
Expected: `42 : Builtin(IntType)` (eval mode)

---

## Level 331: Date/time

**Goal:** `erlang:localtime/0`, `calendar` module.

### 331.1 Current time
```
(now)
```
Expected: Timestamp in milliseconds since epoch.

---

## Level 332: UUID generation

**Goal:** Generate v4 UUIDs.

### 332.1 New UUID
```
(uuid-v4)
```
Expected: String like `"f47ac10b-58cc-4372-a567-0e02b2c3d479"`

---

## Level 333: Base64 encoding

**Goal:** `base64:encode/1`, `base64:decode/1`.

### 333.1 Encode
```
(base64-encode "hello")
```
Expected: `<<"aGVsbG8=">>`

### 333.2 Decode
```
(base64-decode "aGVsbG8=")
```
Expected: `<<"hello">>`

---

## Level 334: Hex encoding

**Goal:** Integer-to-hex and hex-to-integer conversion.

### 334.1 Int to hex
```
(int->hex 255)
```
Expected: `<<"ff">>`

### 334.2 Hex to int
```
(hex->int "ff")
```
Expected: `255`

---

## Level 335: CRC/checksum

**Goal:** `erlang:crc32/1`, `erlang:md5/1`.

### 335.1 CRC32
```
(crc32 "hello")
```
Expected: Integer checksum.

---

## Level 336: Compression

**Goal:** `zlib:zip/1`, `zlib:unzip/1`.

### 336.1 Zip
```
(zip "hello hello hello")
```
Expected: Compressed binary (shorter than input).

### 336.2 Unzip
```
(unzip compressed)
```
Expected: `<<"hello hello hello">>` (original restored)

---

## Level 337: Serialization

**Goal:** `term_to_binary/1`, `binary_to_term/1`.

### 337.1 Serialize
```
(serialize [1 2 3])
```
Expected: Binary blob.

### 337.2 Deserialize
```
(deserialize blob)
```
Expected: `[1,2,3]` (restored)

---

## Level 338: JSON generation

**Goal:** Convert gleamunison terms to JSON strings.

### 338.1 Int to JSON
```
(to-json 42)
```
Expected: `<<"42">>`

### 338.2 List to JSON
```
(to-json [1 2 3])
```
Expected: `<<"[1,2,3]">>`

---

## Level 339: CSV parsing

**Goal:** Parse CSV text into list of rows.

### 339.1 Simple CSV
```
(parse-csv "a,b,c\n1,2,3")
```
Expected: `[[<<"a">>,<<"b">>,<<"c">>],[<<"1">>,<<"2">>,<<"3">>]]`

---

## Level 340: INI parsing

**Goal:** Parse `[section] key=value` config format.

### 340.1 Simple INI
```
(parse-ini "[db]\nhost=localhost\nport=5432")
```
Expected: `{"db": {"host": "localhost", "port": "5432"}}`

---

## Level 341: Markdown→HTML renderer

**Goal:** Full renderer using bootstrapped string ops.

### 341.1 Render heading
```
(md->html "# Hello\n\nWorld")
```
Expected: `"<h1>Hello</h1>\n<p>World</p>"`

---

## Level 342: JSON parser (recursive descent)

**Goal:** Parse JSON string into gleamunison terms.

### 342.1 Parse object
```
(parse-json "{\"a\": 1, \"b\": [2, 3]}")
```
Expected: `{dict, {"a", 1}, {"b", [2, 3]}}`

---

## Level 343: HTTP client

**Goal:** `(http-get url)` returns response body.

### 343.1 GET request
```
(http-get "http://localhost:8080/")
```
Expected: `{ok, {200, "<html>..."}}`

---

## Level 344: Script runner

**Goal:** `(run-script "path")` evaluates a file.

### 344.1 Run script
```
(run-script "tests/all.gleam")
```
Expected: Results of each expression in the file.

---

## Level 345: Interactive debugger

**Goal:** Breakpoint, step over, continue.

### 345.1 Debug expression
```
:debug (add 1 2)
```
Expected: Break at each sub-expression. Type `step`, `continue`, `inspect`.

---

## Level 346: Codebase self-test

**Goal:** Hash/lookup consistency across all stored defs.

### 346.1 Self-test
```
:codebase-check
```
Expected: "All 128 definitions verified. 0 corrupt. 0 missing."

---

## Level 347: Full-stack notes app

**Goal:** Login, create, edit, delete notes.

### 347.1 Create note
```
POST /notes {"title": "Meeting notes", "body": "..."}
```
Expected: Note created, linked to user session.

### 347.2 List user notes
```
GET /notes
```
Expected: JSON list of user's notes with IDs, titles, timestamps.

---

## Level 348: Collaborative editor

**Goal:** WebSocket, operational transform for real-time editing.

### 348.1 Edit document
Two clients connect to `ws://localhost:8080/edit/doc1`.
Client A inserts "hello". Client B sees "hello" appear.
Expected: Both clients converge on same document state.

---

## Level 349: API gateway

**Goal:** Route, auth, rate-limit, log all-in-one.

### 349.1 Gateway pipeline
```
GET /api/v1/users/me
```
Expected: Auth check → rate limit → route to users service → log → response.

---

## Level 350: Package server v2

**Goal:** Upload, browse, search, depend, version.

### 350.1 Publish package
```
POST /packages {"name": "math-lib", "version": "1.0.0", "defs": [...]}
```
Expected: Package published with version. Can be searched and depended on.


## Level 351: Register custom ability
**Goal:** Declare new ability with surface syntax.
### 351.1 Test
```
(ability Math (add int int int) (sub int int int))
```
Expected: Ability registered

---

## Level 352: Multi-op handler module
**Goal:** Handler covering multiple operation indices.
### 352.1 Test
```
(do Math add 1 2)
```
Expected: 3 via effects dispatch

---

## Level 353: Effect forwarding
**Goal:** Console handler delegates to Logger.
### 353.1 Test
```
(do Console print "test")
```
Expected: Logger receives message

---

## Level 354: Composition with results
**Goal:** Handler transforms final value.
### 354.1 Test
```
(handle (add 1 2) (lam (_ cont) (cont (mul 2 (cont nil)))) Math)
```
Expected: 6 (doubled)

---

## Level 355: Abort effect
**Goal:** Discard continuation.
### 355.1 Test
```
(handle (do Abort abort "fail") AbortHandler)
```
Expected: Computation stops

---

## Level 356: State effect
**Goal:** Get and set via process dict.
### 356.1 Test
```
(handle (do State get "count") (do State set "count" 1) StateHandler)
```
Expected: nil then 1

---

## Level 357: Reader effect
**Goal:** Ask returns environment.
### 357.1 Test
```
(handle (do Reader ask) ReaderHandler)
```
Expected: "env-value"

---

## Level 358: Writer effect
**Goal:** Tell accumulates log.
### 358.1 Test
```
(handle (do Writer tell "a") (do Writer tell "b") WriterHandler)
```
Expected: ["a","b"]

---

## Level 359: Choice / non-determinism
**Goal:** Pick from alternatives.
### 359.1 Test
```
(handle (do Choice pick [1 2 3]) ChoiceHandler)
```
Expected: One value selected

---

## Level 360: Error effect
**Goal:** Throw and catch errors.
### 360.1 Test
```
(handle (do Error throw "bad") ErrorHandler)
```
Expected: Error caught

---

## Level 361: Parse error recovery
**Goal:** Continue after parse error.
### 361.1 Test
```
( let
```
Expected: Parse error, then 42 on next eval

---

## Level 362: Name error recovery
**Goal:** NameNotFound doesn't corrupt state.
### 362.1 Test
```
nonexistent
```
Expected: Error, then subsequent define works

---

## Level 363: Type error recovery
**Goal:** Type mismatch doesn't corrupt cache.
### 363.1 Test
```
(add "hello" 1)
```
Expected: Type error, then 42 on next eval

---

## Level 364: Runtime error handling
**Goal:** Try catches runtime errors.
### 364.1 Test
```
(try (add "bad" "args") (lam e "caught"))
```
Expected: "caught"

---

## Level 365: Error after define
**Goal:** Define works after error.
### 365.1 Test
```
(define a 1) (add a "bad") (define b 2)
```
Expected: a defined, error, b defined

---

## Level 366: 10 sequential errors
**Goal:** REPL doesn't degrade.
### 366.1 Test
```
nonexistent ×10 then 42
```
Expected: All errors clear, 42 works

---

## Level 367: Parse error line/col
**Goal:** Accurate position.
### 367.1 Test
```
(let x
  "hello"
```
Expected: Error at line 1, col 7

---

## Level 368: Type error message
**Goal:** "expected Int got Text".
### 368.1 Test
```
(add "hello" 42)
```
Expected: Clear type mismatch message

---

## Level 369: Crash recovery
**Goal:** Bad arg doesn't crash REPL.
### 369.1 Test
```
(ffi-crash)
```
Expected: Error printed, REPL continues

---

## Level 370: Handler crash recovery
**Goal:** Process dict cleaned.
### 370.1 Test
```
(handle (do Console print "x") (lam (_ _) (error "crash")))
```
Expected: Error caught, PD clean

---

## Level 371: Atom table baseline
**Goal:** Record atom count at startup.
### 371.1 Test
```
:atoms
```
Expected: Baseline count recorded

---

## Level 372: Atoms after 100 evals
**Goal:** Grow < 50 atoms.
### 372.1 Test
```
42 ×100 then :atoms
```
Expected: < 50 atom growth

---

## Level 373: Atoms after 100 defines
**Goal:** ~5 atoms per define.
### 373.1 Test
```
define v0-v99 then :atoms
```
Expected: < 200 total growth

---

## Level 374: Process count
**Goal:** No orphan processes.
### 374.1 Test
```
:processes before/after request
```
Expected: Returns to baseline

---

## Level 375: Insert memory
**Goal:** Memory per definition.
### 375.1 Test
```
insert 1 def, measure
```
Expected: < 1 KB per def

---

## Level 376: 10K defs memory
**Goal:** 10,000 defs total.
### 376.1 Test
```
insert 10K defs, :memory
```
Expected: < 10 MB total

---

## Level 377: Loader module count
**Goal:** Old modules purged.
### 377.1 Test
```
:modules before/after 100 evals
```
Expected: Count stable

---

## Level 378: Purge success rate
**Goal:** soft_purge returns true.
### 378.1 Test
```
(unload-binary m_...)
```
Expected: 100% success

---

## Level 379: Memory leak detection
**Goal:** 1000 eval loop.
### 379.1 Test
```
(bench (lam () 42) 1000)
```
Expected: Heap stable after warmup

---

## Level 380: Binary cleanup
**Goal:** No orphaned binaries.
### 380.1 Test
```
:binaries before/after 100 evals
```
Expected: Count stable

---

## Level 381: Deep nesting
**Goal:** 100 levels of parens.
### 381.1 Test
```
(let a0 (let a1 ... (let a99 1 a99) ...) a1) a0)
```
Expected: 1

---

## Level 382: Long identifier
**Goal:** 500-char name.
### 382.1 Test
```
(define long-name... 42) long-name...
```
Expected: 42

---

## Level 383: Large integer
**Goal:** 100-digit int.
### 383.1 Test
```
1234567890... ×10
```
Expected: Parses correctly

---

## Level 384: Empty program
**Goal:** Empty input handled.
### 384.1 Test
```
(empty-line)
```
Expected: Silent re-prompt

---

## Level 385: Comments everywhere
**Goal:** ; in expressions.
### 385.1 Test
```
42 ; comment
```
Expected: 42

---

## Level 386: Escaped quotes
**Goal:** Strings with \".
### 386.1 Test
```
"hello \"world\""
```
Expected: hello "world"

---

## Level 387: Unicode identifiers
**Goal:** Greek/CJK names.
### 387.1 Test
```
(define α 42) α
```
Expected: 42

---

## Level 388: Mixed whitespace
**Goal:** Tabs and spaces.
### 388.1 Test
```
	42
```
Expected: 42

---

## Level 389: Parser performance
**Goal:** 10K parens in < 100ms.
### 389.1 Test
```
deeply nested 10K parens
```
Expected: < 100ms parse time

---

## Level 390: Tokenizer performance
**Goal:** 100K tokens in < 1s.
### 390.1 Test
```
100K-element list
```
Expected: < 1s tokenize time

---

## Level 391: Constant folding
**Goal:** add 2 3 → literal 5.
### 391.1 Test
```
(add 2 3)
```
Expected: 5

---

## Level 392: Dead let elimination
**Goal:** Unused binding removed.
### 392.1 Test
```
(let x 1 42)
```
Expected: 42 (no V0 ref)

---

## Level 393: Inline lambda
**Goal:** ((lam x body) arg) inlined.
### 393.1 Test
```
((lam x (add x 1)) 41)
```
Expected: 42

---

## Level 394: Match simplification
**Goal:** Single case → direct.
### 394.1 Test
```
(match 42 (42 "yes"))
```
Expected: "yes"

---

## Level 395: Let chaining
**Goal:** Nested begin...end.
### 395.1 Test
```
(let a 1 (let b 2 (add a b)))
```
Expected: 3

---

## Level 396: Apply chain flatten
**Goal:** Minimal apply calls.
### 396.1 Test
```
(add (add 1 2) 3)
```
Expected: 6

---

## Level 397: Direct module call
**Goal:** No apply for genesis.
### 397.1 Test
```
(add 1 2)
```
Expected: 3 (direct call)

---

## Level 398: Dead branch
**Goal:** Unreachable arm removed.
### 398.1 Test
```
(match 1 (2 "unr") (x "fb"))
```
Expected: "fb"

---

## Level 399: 1000 def compile
**Goal:** Unit compiles fast.
### 399.1 Test
```
1000-def unit compile
```
Expected: < 5s

---

## Level 400: BEAM size patterns
**Goal:** Size varies by pattern.
### 400.1 Test
```
compare sizes of 3 patterns
```
Expected: Measured variance

---

