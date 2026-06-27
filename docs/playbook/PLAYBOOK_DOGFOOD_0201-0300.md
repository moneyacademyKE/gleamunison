## Level 201: Codebase integrity check

**Goal:** Verify every definition in the codebase has a correct hash.

### 201.1 Hash consistency
Insert a definition, then verify the hash matches its bytes:
```
(define test_val 42)
```
Then query the codebase adapter to verify `hash(def_bytes) == stored_ref`.

### Known issues
- Requires direct codebase API access (Gleam host code, not REPL)

---

## Level 202: Codebase repair

**Goal:** Detect and fix corrupt definitions in storage.

### 202.1 Rehash
After inserting N definitions, rehash each and verify:
- Definitions with matching hashes are kept
- Definitions with mismatched hashes are flagged

---

## Level 203: Storage adapter benchmark

**Goal:** Measure throughput of in-memory vs DETS vs partitioned storage.

### 203.1 Insert throughput
Time 1000 inserts under each backend:
```gleam
let start = ffi_monotonic_time()
// insert 1000 defs
let elapsed = ffi_monotonic_time() - start
```
Expected: In-memory fastest, then DETS, then partitioned (more file handles)

---

## Level 204: 100K definition stress

**Goal:** Insert 100,000 unique definitions and measure time/memory.

### 204.1 Mass insert
Insert 100K definitions with sequential integer terms:
```
// Generated: (define v0 0) ... (define v99999 99999)
```
Expected: All inserted without crash. Time is sub-linear due to hash-based dedup.

---

## Level 205: Concurrent codebase access

**Goal:** Test multiple processes sharing a DETS-backed codebase.

### 205.1 Parallel inserts
Spawn 10 processes, each inserting 100 definitions into the same DETS store.
Expected: All 1000 definitions stored without corruption.

---

## Level 206: Snapshot serialization

**Goal:** Export entire codebase to a portable binary format.

### 206.1 Export
Insert 10 definitions, then export the codebase to bytes:
```
(codebase_export)
```
Expected: Binary blob containing all 10 defs with their hashes.

---

## Level 207: Snapshot restore

**Goal:** Rebuild codebase from an exported binary snapshot.

### 207.1 Import
From the snapshot bytes from Level 206:
```
(codebase_import snapshot_bytes)
```
Expected: All 10 definitions restored with correct hashes.

---

## Level 208: Codebase GC (mark and sweep)

**Goal:** Remove unreachable definitions from storage.

### 208.1 GC cycle
Insert 100 defs where only 50 are reachable from the root set.
Run GC. Verify 50 defs remain and the unreachable 50 are gone.

---

## Level 209: Adapter migration

**Goal:** Copy all definitions from one storage adapter to another.

### 209.1 Migrate in-memory to DETS
```gleam
let src = inmemory()
let dst = dets("/tmp/migrate_test.dets")
migrate(src, dst)
```
Expected: All definitions readable from DETS.

---

## Level 210: Definition diff

**Goal:** Compare two codebases and list differences.

### 210.1 Diff A vs B
Insert def [A, B] in codebase A and [A, C] in codebase B.
Run diff. Expected: B is new in A, C is new in B, A is common.

---

## Level 211: REPL history

**Goal:** Arrow keys recall previous expressions.

### 211.1 History recall
Type `42`, press Enter, then press Up.
Expected: `42` appears again on the input line.

---

## Level 212: Meta-commands

**Goal:** `:help`, `:env`, `:defs`, `:gc`, `:version` commands.

### 212.1 Help command
```
:help
```
Expected: List of available meta-commands with descriptions.

### 212.2 Defs command
```
:defs
```
Expected: List of user-defined names (from prev_defs).

---

## Level 213: Expression inspector

**Goal:** Show AST, type, and compiled Erlang for an expression.

### 213.1 Inspect 42
```
(inspect 42)
```
Expected: `AST: Int(42), Type: Builtin(IntType), Erlang: 42`

---

## Level 214: Trace mode

**Goal:** Step-by-step execution trace of an expression.

### 214.1 Trace add
```
:trace (add 1 2)
```
Expected: Each reduction step printed, final result `3`

---

## Level 215: Profile mode

**Goal:** Time breakdown per pipeline phase.

### 215.1 Profile expression
```
:profile (list-length (range 1 1000))
```
Expected: Parse: 0.2ms, Elab: 0.5ms, Compile: 1.1ms, Load: 0.3ms, Eval: 0.05ms

---

## Level 216: Multi-line editing

**Goal:** Edit across lines with cursor navigation.

### 216.1 Multi-line entry
Type `(let x 1` then Enter (bracket not closed, REPL continues):
Expected: Continuation prompt `.. `, type `x)` to complete.

---

## Level 217: Tab completion

**Goal:** Tab completes names from bootstrapped + user defs.

### 217.1 Complete "st"
Type `st` then Tab:
Expected: `string-concat`, `string-length`, `string-contains?` etc. suggested.

---

## Level 218: Color output

**Goal:** Syntax-highlighted results and errors.

### 218.1 Colored result
Type `42`:
Expected: `42` in yellow, `: Builtin(IntType)` in green (ANSI colors).

---

## Level 219: Error pretty-printer

**Goal:** Structured error display with source context.

### 219.1 Parse error display
Type `(let`:
Expected:
```
Parse Error at line 1, col 5:
  (let
      ^
  Unexpected end of expression
```

---

## Level 220: Script loading

**Goal:** Load and evaluate a file.

### 220.1 Load script
Create `test.gleam` with `42`, then in REPL:
```
(load "test.gleam")
```
Expected: `42 : Builtin(IntType)`

---

## Level 221: WebSocket endpoint

**Goal:** HTTP→WebSocket upgrade for real-time communication.

### 221.1 Upgrade handshake
```
GET /ws HTTP/1.1
Upgrade: websocket
```
Expected: 101 Switching Protocols, WebSocket frame exchange.

---

## Level 222: SSE streaming

**Goal:** Server-Sent Events for continuous push.

### 222.1 SSE endpoint
```
GET /events
```
Expected: `text/event-stream` with periodic data frames.

---

## Level 223: Static file serving

**Goal:** Serve files from a directory.

### 223.1 GET static file
```
curl http://localhost:8080/files/test.txt
```
Expected: 200 OK with file contents, proper Content-Type.

---

## Level 224: Middleware pipeline

**Goal:** Chain request pre/post processing.

### 224.1 Logging middleware
Each request prints `[timestamp] METHOD /path -> STATUS` to server stdout.

---

## Level 225: Web REPL console

**Goal:** Browser-based REPL via WebSocket.

### 225.1 Web eval
Open `http://localhost:8080/`, type `42` in the web REPL input:
Expected: Result `42 : Builtin(IntType)` displayed on the page.

---

## Level 226: Path routing

**Goal:** Declarative route definitions with path parameters.

### 226.1 User route
```
GET /users/42
```
Expected: Route matches `/users/:id` with `id = "42"`.

---

## Level 227: JSON response formatting

**Goal:** Auto-encode gleamunison terms as JSON.

### 227.1 JSON API
```
GET /api/echo?msg=hello
```
Expected: `{"msg": "hello", "type": "Text"}` as JSON.

---

## Level 228: CORS headers

**Goal:** Cross-Origin Resource Sharing support.

### 228.1 Preflight
```
OPTIONS /api/echo
Origin: http://example.com
```
Expected: 200 with `Access-Control-Allow-Origin: *`.

---

## Level 229: Rate limiting

**Goal:** Token bucket rate limiter per IP.

### 229.1 Rate limit hit
Send 100 requests in 1 second from the same IP.
Expected: Request 101 returns 429 Too Many Requests.

---

## Level 230: Request logging

**Goal:** Structured request/response logging.

### 230.1 Log format
Each request logs: `[2026-06-27 10:00:00] GET / 200 1.2ms 512B`

---

## Level 231: Todo app v2

**Goal:** DETS-backed todo list with categories and search.

### 231.1 Create todo
```
POST /todos {"title": "Buy milk", "category": "shopping"}
```
Expected: `{"id": 1, "title": "Buy milk", "category": "shopping"}`

### 231.2 List by category
```
GET /todos?category=shopping
```
Expected: `{"todos": [{"id": 1, ...}]}`

---

## Level 232: Chat server

**Goal:** WebSocket broadcast with rooms.

### 232.1 Join room
Connect to `ws://localhost:8080/chat/room1`:
```
{"type": "join", "user": "alice"}
```
Expected: `{"type": "system", "msg": "alice joined"}` broadcast to room.

---

## Level 233: URL shortener

**Goal:** POST to create short URLs, GET to redirect.

### 233.1 Create short URL
```
POST /shorten {"url": "https://example.com/long/path"}
```
Expected: `{"short": "http://localhost:8080/s/abc123"}`

### 233.2 Follow redirect
```
GET /s/abc123
```
Expected: 302 redirect to `https://example.com/long/path`.

---

## Level 234: KV store

**Goal:** Full CRUD REST API for key-value pairs.

### 234.1 Create
```
PUT /kv/mykey {"value": 42}
```
Expected: `{"status": "created"}`

### 234.2 Read
```
GET /kv/mykey
```
Expected: `{"key": "mykey", "value": 42}`

### 234.3 Delete
```
DELETE /kv/mykey
```
Expected: `{"status": "deleted"}`

---

## Level 235: Static site generator

**Goal:** Markdown → HTML with templates.

### 235.1 Build
Process a markdown file with YAML frontmatter:
```
---
title: My Page
---
# Hello
World
```
Expected: `<h1>Hello</h1>\n<p>World</p>` wrapped in template.

---

## Level 236: Blog engine

**Goal:** Posts, tags, comments, RSS feed.

### 236.1 Create post
```
POST /blog {"title": "My Post", "body": "...", "tags": ["gleamunison"]}
```
Expected: Post created with ID, slug, timestamp.

---

## Level 237: Pastebin

**Goal:** Share code/text snippets via short URLs.

### 237.1 Create paste
```
POST /paste {"content": "42", "language": "gleamunison", "expires": 3600}
```
Expected: `{"url": "http://localhost:8080/p/a1b2c3"}`

---

## Level 238: Poll app

**Goal:** Create polls, vote, see results.

### 238.1 Create poll
```
POST /polls {"question": "Best language?", "options": ["Gleam", "Erlang", "Both"]}
```
Expected: Poll created with unique ID.

---

## Level 239: Guestbook

**Goal:** Signed visitor messages with timestamps.

### 239.1 Sign guestbook
```
POST /guestbook {"name": "Alice", "message": "Great runtime!"}
```
Expected: `{"entry": {"id": 1, "name": "Alice", "message": "Great runtime!", "time": "..."}}`

---

## Level 240: File upload server

**Goal:** Multipart form file upload and storage.

### 240.1 Upload file
```
POST /upload (multipart with file "photo.jpg")
```
Expected: `{"url": "/files/photo.jpg", "size": 12345}`

---

## Level 241: Form validation library

**Goal:** Validate and transform input data.

### 241.1 Validate email
```
(validate-email "user@example.com")
```
Expected: `{ok, "user@example.com"}` or `{error, "invalid email"}`

---

## Level 242: HTML templating

**Goal:** Compile templates from gleamunison strings.

### 242.1 Render template
```
(render "<h1>{{title}}</h1>" {"title": "Hello"})
```
Expected: `"<h1>Hello</h1>"`

---

## Level 243: Routing library

**Goal:** Declarative route definitions.

### 243.1 Define route
```
(route "/users/:id" (lam (params) (get-user (dict-get params "id"))))
```
When matched with `/users/42`, calls handler with `{"id": "42"}`.

---

## Level 244: Session management

**Goal:** Cookie-based sessions with DETS storage.

### 244.1 Create session
```
POST /session {"user": "alice"}
```
Expected: `Set-Cookie: session_id=abc123; HttpOnly` in response headers.

---

## Level 245: Auth middleware

**Goal:** Login-required route wrapper.

### 245.1 Protected route
```
GET /admin
```
Without session cookie: Expected 401 Unauthorized.
With valid session: Expected 200 OK.

---

## Level 246: Migration tool

**Goal:** Codebase schema version management.

### 246.1 Version check
```
(migrate-status)
```
Expected: `{"current_version": 3, "latest_version": 5, "pending": ["v4", "v5"]}`

---

## Level 247: Background jobs

**Goal:** Spawn worker processes from a job queue.

### 247.1 Enqueue job
```
(enqueue-job "send-email" {"to": "user@example.com", "body": "..."})
```
Expected: `{"job_id": "job_001", "status": "queued"}`
Worker picks up and processes the job asynchronously.

---

## Level 248: Webhook receiver

**Goal:** Accept and dispatch HTTP callbacks.

### 248.1 Register webhook
```
POST /webhooks {"url": "https://example.com/callback", "events": ["define", "eval"]}
```
Expected: `{"id": "wh_001"}`. When a `define` event occurs, POST to the callback URL.

---

## Level 249: Admin dashboard

**Goal:** System stats, defs browser, process monitor.

### 249.1 Dashboard
```
GET /admin
```
Expected: HTML page showing: codebase size, atom count, process count, loaded modules, recent evals.

---

## Level 250: API gateway

**Goal:** Unified routing, auth, rate-limit for microservices.

### 250.1 Gateway
```
GET /api/v1/users
```
Expected: Route to users service, auth check passes, rate limit not exceeded → 200 OK.

---

## Level 251: S-expression parser in gleamunison

**Goal:** Parse surface syntax from within gleamunison.

### 251.1 Tokenize "(+ 1 2)"
```
(tokenize "(+ 1 2)")
```
Expected: `[LParen, Symbol("+"), Int(1), Int(2), RParen]`

---

## Level 252: Pretty-printer

**Goal:** Convert AST back to surface syntax string.

### 252.1 Unparse integer
```
(unparse (ast.Int 42))
```
Expected: `"42"`

---

## Level 253: Code generation

**Goal:** Build AST from data, compile, and run.

### 253.1 Build and eval
Build `(add 1 2)` as AST, compile, load, eval.
Expected: Result `3`.

---

## Level 254: Compiler self-test

**Goal:** Compile a definition, load, eval, verify result.

### 254.1 Self-test pipeline
```gleam
let def = ast.TermDef(term: ast.Int(42), typ: ast.Builtin(IntType))
let Ok(beam) = compile.compile_definition(comp, def, ref)
let Ok(_) = loader.ensure_loaded(ld, ref, def)
let Ok(Result) = ffi_eval_module(module_name_for(ref))
```
Expected: `"42"` as the evaluation result string.

---

## Level 255: Version info

**Goal:** Return gleamunison version metadata.

### 255.1 Get version
```
(gleamunison-version)
```
Expected: `{"version": "0.1.0", "genesis_count": 50, "levels": 1000}`

---

## Level 256: Test runner

**Goal:** Run multiple test expressions and collect results.

### 256.1 Run tests
Define and run a test suite:
```
(run-tests)
```
Expected: "3 passed, 0 failed, 5 total"

---

## Level 257: Coverage tracker

**Goal:** Track which definitions/exercises were loaded.

### 257.1 Coverage report
```
:coverage
```
Expected: List of loaded modules, count of evals per module.

---

## Level 258: Doc generator

**Goal:** Extract comments and produce HTML documentation.

### 258.1 Generate docs
```
(doc-gen)
```
Expected: HTML documentation of all bootstrapped operations.

---

## Level 259: Code formatter

**Goal:** Canonical S-expression formatting.

### 259.1 Format expression
```
(format "(let x 1 x)")
```
Expected: `"(let x 1 x)"` or multi-line formatted version.

---

## Level 260: Static analysis

**Goal:** Detect unused defs, shadowed names, dead code.

### 260.1 Unused detection
```
(analyze (define x 1) (define y 2) y)
```
Expected: Warning: `x` is defined but never used.

---

## Level 261: Microbenchmark framework

**Goal:** Time any expression with microsecond precision.

### 261.1 Benchmark add
```
(bench (lam () (add 1 2)) 10000)
```
Expected: `{"mean": 0.42, "min": 0.31, "max": 1.23, "samples": 10000}` (μs)

---

## Level 262: Compile benchmark

**Goal:** Measure parse/elaborate/compile time per expression.

### 262.1 Compile 1000 ints
Time compilation of `42` repeated 1000 times.
Expected: Mean compile time < 2000 μs per expression.

---

## Level 263: Runtime benchmark

**Goal:** Measure eval/call overhead.

### 263.1 Eval 42
```
(bench (lam () 42) 100000)
```
Expected: Mean eval time < 100 μs.

---

## Level 264: Memory profiling

**Goal:** Track process heap growth during evaluation.

### 264.1 Heap growth
Before and after 100 evals, measure `erlang:process_info(self(), heap_size)`.
Expected: Heap size stable (within noise), no leak.

---

## Level 265: Atom table monitoring

**Goal:** Monitor `erlang:system_info(atom_count)` during session.

### 265.1 Atom growth
```
:atoms
```
Expected: Current atom count. After 100 evals, count increases by < 50.

---

## Level 266: Process count monitoring

**Goal:** Monitor `erlang:system_info(process_count)`.

### 266.1 Process leak
Start server, measure process count. Send 100 requests, measure again.
Expected: Process count stable (no orphaned processes).

---

## Level 267: 1M definitions stress

**Goal:** Stress test with million-entry codebase.

### 267.1 Million inserts
Insert 1,000,000 unique definitions.
Expected: Insert time measured, memory usage reported.

---

## Level 268: Ops per second

**Goal:** Measure codebase operations throughput.

### 268.1 Throughput
```
(bench (lam () (define x (add 1 2))) 1000)
```
Expected: Ops/sec reported for defines, evals, lookups.

---

## Level 269: Web throughput

**Goal:** Requests/second on `/eval` and `/counter` endpoints.

### 269.1 Load test
```
ab -n 1000 -c 10 http://localhost:8080/
```
Expected: Throughput > 100 req/s, no errors.

---

## Level 270: Connection scaling

**Goal:** 1000 concurrent connections to the web server.

### 270.1 Concurrent clients
```
ab -n 1000 -c 100 http://localhost:8080/
```
Expected: All requests complete. No connection drops.

---

## Level 271: Node discovery

**Goal:** Connect to EPMD for distributed Erlang.

### 271.1 Ping node
```
(net-ping "gleamunison@localhost")
```
Expected: `pong` if node is reachable, `pang` if not.

---

## Level 272: Remote spawn

**Goal:** Spawn a function on a remote node.

### 272.1 Spawn remote
```
(spawn 'gleamunison@other_node' (lam () 42))
```
Expected: PID on remote node, result of `42` when `recv`'d.

---

## Level 273: Remote send

**Goal:** Send a message to a registered remote process.

### 273.1 Send to remote
```
(send {worker, 'gleamunison@other_node'} "hello")
```
Expected: Message delivered to registered process on remote node.

---

## Level 274: Distributed codebase sync

**Goal:** Sync definitions between two DETS stores.

### 274.1 Two-way sync
Codebase A has defs [1,2]. Codebase B has defs [2,3].
After sync, both have [1,2,3].

---

## Level 275: Distributed KV store

**Goal:** Partitioned key-value store across cluster.

### 275.1 Put and get across nodes
```
(put "key1" 42) ; stored on node A
(get "key1")     ; retrieved from node A
```
Expected: `42` retrieved regardless of which node handles the get.

---

## Level 276: Cluster membership

**Goal:** Join/leave detection in a cluster.

### 276.1 Node join
Start a new node that connects to the cluster.
Expected: Existing nodes detect the join event.

---

## Level 277: Failure detection

**Goal:** Detect when a remote node becomes unreachable.

### 277.1 Kill node
Kill one node in a 3-node cluster.
Expected: Other nodes detect the failure within the timeout window.

---

## Level 278: Leader election

**Goal:** Lowest-ID node becomes coordinator.

### 278.1 Elect leader
In a 3-node cluster, the node with the lowest name is elected leader.
After leader dies, remaining nodes re-elect.

---

## Level 279: Distributed counter

**Goal:** Atomic increment across nodes.

### 279.1 Increment across cluster
```
(dcounter-inc "global-counter")
```
Each node can increment. The total reflects all increments.

---

## Level 280: Cross-node pub/sub

**Goal:** Publish/subscribe messaging across nodes.

### 280.1 Subscribe and publish
Node B subscribes to "events". Node A publishes `{"type": "user_created"}`.
Expected: Node B receives the message.

---

## Level 281: Custom Math ability

**Goal:** Bootstrapped ability with typed operations.

### 281.1 Math ability
```
(do Math add 1 2)
```
Expected: `3` via effects dispatch to Math handler.

---

## Level 282: Show ability

**Goal:** Polymorphic `(show x)` → string for any type.

### 282.1 Show integer
```
(do Show show 42)
```
Expected: `<<"42">>` (converted to string via Erlang `~tp`)

### 282.2 Show text
```
(do Show show "hello")
```
Expected: `<<"\"hello\"">>` (quoted string representation)

---

## Level 283: Stateful handler

**Goal:** Handler that accumulates state across effect calls.

### 283.1 Counter handler
```
(do State get "count")
(do State set "count" 1)
(do State get "count")
```
Expected: First get returns `0`, set stores `1`, second get returns `1`.

---

## Level 284: Effect composition

**Goal:** Two abilities active in the same computation.

### 284.1 Console + State
```
(do Console print (do State get "count"))
```
Expected: Console prints the current value of `"count"` from State.

---

## Level 285: Handler forwarding

**Goal:** Handler for A delegates unhandled ops to handler for B.

### 285.1 Forward
```
(handle (do Logger log "msg") LoggerHandler) (do Console print "hi") Console)
```
Expected: Logger forwards `Console` ops to Console handler.

---

## Level 286: Abort effect

**Goal:** `(do Abort abort msg)` discards the continuation.

### 286.1 Abort
```
(handle (do Abort abort "fail") AbortHandler)
```
Expected: Computation stops, result from abort handler.

---

## Level 287: Choice effect

**Goal:** Non-deterministic selection via effects.

### 287.1 Pick
```
(handle (do Choice pick [1 2 3]) ChoiceHandler)
```
Expected: Handler picks one value (e.g., `1`) non-deterministically.

---

## Level 288: Reader effect

**Goal:** `(do Reader ask)` returns environment value.

### 288.1 Ask
```
(handle (do Reader ask) (lam (_ cont) (cont "env-value")) Reader)
```
Expected: `<<"env-value">>`

---

## Level 289: Writer effect

**Goal:** `(do Writer tell msg)` accumulates log output.

### 289.1 Tell
```
(handle (do Writer tell "step1") (do Writer tell "step2") WriterHandler)
```
Expected: Handler accumulates `["step1", "step2"]` in log.

---

## Level 290: State effect via effects runtime

**Goal:** Full State ability using process dictionary.

### 290.1 Get and set
```
(handle (do State get) (do State set "x" 42) (do State get) StateHandler)
```
Expected: First get returns `nil`, set stores `42`, second get returns `42`.

---

## Level 291: Input validation

**Goal:** Validate string constraints.

### 291.1 Validate length
```
(validate "toolong" (lam s (gt? (string-length s) 5)))
```
Expected: `{error, "validation failed"}` (string too long)

---

## Level 292: Rate limiting

**Goal:** Token bucket algorithm, per-IP.

### 292.1 Rate limit config
```
(rate-limit-config 100 60) ; 100 requests per 60 seconds
```
Expected: Rate limiter allows 100 requests, rejects 101st with `rate_exceeded`.

---

## Level 293: CORS enforcement

**Goal:** Origin validation with preflight handling.

### 293.1 Valid origin
```
OPTIONS /api/data
Origin: https://myapp.com
```
Expected: 200 with `Access-Control-Allow-Origin: https://myapp.com`

### 293.2 Invalid origin
```
OPTIONS /api/data
Origin: https://evil.com
```
Expected: 403 Forbidden

---

## Level 294: CSRF protection

**Goal:** Token-based cross-site request forgery protection.

### 294.1 Valid token
```
POST /api/data
X-CSRF-Token: abc123
```
Expected: 200 OK (token validated)

---

## Level 295: Sessions

**Goal:** Signed cookie sessions with expiry.

### 295.1 Create session
```
POST /login {"user": "alice", "password": "secret"}
```
Expected: `Set-Cookie: session=abc123; HttpOnly; Secure; Max-Age=3600`

---

## Level 296: Password hashing

**Goal:** Hash passwords with salt.

### 296.1 Hash and verify
```
(hash-password "mypassword")
(verify-password "mypassword" hash)
```
Expected: First returns hash string. Second returns `1` (match).

---

## Level 297: Token auth

**Goal:** Bearer token verification.

### 297.1 Valid token
```
GET /api/secure
Authorization: Bearer valid_token_123
```
Expected: 200 OK

---

## Level 298: RBAC

**Goal:** Role-based access control middleware.

### 298.1 Admin role
```
GET /admin
Role: admin
```
Expected: 200 OK

### 298.2 User role
```
GET /admin
Role: user
```
Expected: 403 Forbidden

---

## Level 299: Audit log

**Goal:** Timestamped, signed operation log.

### 299.1 Log entry
Each define/eval operation logs: `[timestamp] user:alice action:define target:x`
Expected: Log queryable via `:audit-log` meta-command.

---

## Level 300: Security scan

**Goal:** Inventory all bootstrapped ops for misuse patterns.

### 300.1 Scan report
```
:security-scan
```
Expected: Report listing all 50 genesis modules with risk level and usage patterns.

---

