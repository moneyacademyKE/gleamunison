# Dogfooding Playbook — Levels 1101–1150

Tests covering pipeline phases, storage adapters, sync protocol, REPL edge cases,
ability handler validation, error recovery patterns, concurrency primitives,
dashboard API operations, performance stress, and integration certification.

All levels are real implementations in `src/dogfood_v4.gleam`.

---

## Level 1101–1105: Pipeline phases

**Level 1101** — Parse-only pipeline: parse integer literal.
- **Expected:** `42` parses to `SInt(42)`.

**Level 1102** — Tokenize to AST: lex and parse let expression.
- **Expected:** Token count matches, parse succeeds.

**Level 1103** — Hash-only pipeline: identical terms produce identical hashes.
- **Expected:** `hash_equal(h1, h2)` is True.

**Level 1104** — Compile-only: lambda term → hash → codebase insert.
- **Expected:** Successful insert.

**Level 1105** — Full pipeline latency: 4 parses in sequence.
- **Expected:** All parses complete, prints timing.

---

## Level 1106–1110: Storage adapters

**Level 1106** — In-memory storage insert.
- **Expected:** `ffi_storage_insert` returns `Ok(Nil)`.

**Level 1107** — Storage lookup after insert.
- **Expected:** Returns inserted value.

**Level 1108** — Storage missing key lookup.
- **Expected:** Returns error for nonexistent key.

**Level 1109** — Storage overwrite: insert twice, lookup returns latest.
- **Expected:** Lookup returns second value.

**Level 1110** — Storage bulk insert: 100 inserts benchmarked.
- **Expected:** All 100 inserts complete, prints timing.

---

## Level 1111–1115: Sync protocol

**Level 1111** — Sync state creation.
- **Expected:** `new_sync_state()` returns valid state.

**Level 1112** — Sync types: PeerId construction.
- **Expected:** `PeerId("test-node")` constructs.

**Level 1113** — Codebase + sync integration: insert definition + create sync state.
- **Expected:** Both succeed.

**Level 1114** — Hash-to-debug-string: hex length is 64.
- **Expected:** `hash_to_debug_string` produces 64-character hex.

**Level 1115** — Multi-def sync ready: 3 definitions inserted into codebase.
- **Expected:** All 3 inserts succeed.

---

## Level 1116–1120: REPL edge cases

**Level 1116** — Empty input parse error.
- **Expected:** `parse_string("")` returns error.

**Level 1117** — Comment line parse.
- **Expected:** `parse_string("; comment")` handles gracefully.

**Level 1118** — Quote shorthand: `'x` parses.
- **Expected:** Parsed as `(quote x)` or equivalent.

**Level 1119** — Bracket counting: unbalanced input.
- **Expected:** `count_brackets` returns non-zero.

**Level 1120** — Bracket counting: balanced input.
- **Expected:** `count_brackets` returns 0.

---

## Level 1121–1125: Ability handler validation

**Level 1121** — Basic handler validation.
- **Expected:** `validate_handler` returns result.

**Level 1122** — Empty handler validation.
- **Expected:** Handle gracefully (builtin may not be in cache).

**Level 1123** — Handler arity mismatch.
- **Expected:** Validation reports error or passes (depends on cache state).

**Level 1124** — All 5 ability builtins accessible.
- **Expected:** `builtin_state_get`, `builtin_state_put`, `builtin_io_read_line`, `builtin_process_spawn` all resolve.

**Level 1125** — 50+ genesis builtins accessible.
- **Expected:** `builtin_int_add`, `builtin_sub`, `builtin_eq`, `builtin_list_map`, `builtin_json_parse`, `builtin_http_get` all resolve.

---

## Level 1126–1130: Error recovery

**Level 1126** — Parse recovery after unclosed paren error.
- **Expected:** Second parse of valid expression succeeds despite prior error.

**Level 1127** — Hash of Hole term stability.
- **Expected:** `hash_of_definition` on Hole succeeds.

**Level 1128** — Idempotent insert: same definition inserted twice.
- **Expected:** Content-addressed store accepts duplicate without error.

**Level 1129** — Large integer term (9999999999) insert.
- **Expected:** Codebase insert succeeds.

**Level 1130** — Negative integer term (-999999) insert.
- **Expected:** Codebase insert succeeds.

---

## Level 1131–1135: Concurrency primitives

**Level 1131** — Process builtins accessible.
- **Expected:** spawn, self, send, recv all resolve.

**Level 1132** — Concurrent counter stability: multiple counters with different names.
- **Expected:** No crash for any counter operation.

**Level 1133** — Concurrent gauge updates: multiple values set.
- **Expected:** No crash for any gauge operation.

**Level 1134** — Timer builtins accessible.
- **Expected:** sleep, now resolve.

**Level 1135** — Concurrent JSON encode: 5 encodes of different types.
- **Expected:** All succeed.

---

## Level 1136–1140: Dashboard API

**Level 1136** — Health readiness check.
- **Expected:** `health.readiness()` returns boolean.

**Level 1137** — Config load.
- **Expected:** `config.load()` returns valid config.

**Level 1138** — Trace capture + list.
- **Expected:** Captured trace appears in list.

**Level 1139** — Multi-trace capture: 3 traces with GET/POST/PUT.
- **Expected:** All 3 traces captured.

**Level 1140** — Dashboard logging: all 4 levels.
- **Expected:** debug, info, warn, error emit without crash.

---

## Level 1141–1145: Performance stress

**Level 1141** — 1000 hash throughput.
- **Expected:** Completes under 2 seconds, prints timing.

**Level 1142** — 1000 encode throughput.
- **Expected:** Completes under 5 seconds, prints timing.

**Level 1143** — 1000 log throughput.
- **Expected:** Completes, prints timing.

**Level 1144** — 10000 counter operations.
- **Expected:** Completes, prints timing.

**Level 1145** — 1000 property checks.
- **Expected:** Completes, prints timing.

---

## Level 1146–1150: Integration certification

**Level 1146** — Full AST variant coverage: 15 term types hashed.
- **Expected:** All 15 produce valid hashes without crash.

**Level 1147** — Stdlib full coverage: filepath, datetime, crypto, JSON, metrics, log.
- **Expected:** All 7 modules exercise without error.

**Level 1148** — Operations full coverage: config, health, metrics, prop test, traces.
- **Expected:** All 5 modules exercise without error.

**Level 1149** — Pipeline end-to-end: parse integer → elaborate → typecheck.
- **Expected:** `elaborate_unit` succeeds.

**Level 1150** — v1.1.0 full certification: prints 4-batch summary.
- **Expected:** Reports 171 total real dogfood levels.
