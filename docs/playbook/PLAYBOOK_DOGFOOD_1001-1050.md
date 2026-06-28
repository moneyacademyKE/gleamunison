# Dogfooding Playbook — Levels 1001–1050

Tests 50 new levels exercising v1.1.0 features: guard clauses, use expression,
holes, stdlib modules (http_client, json, datetime, filepath, crypto, template),
operations (logging, config, health, metrics), Darklang traces, property-based
testing, and linearity enforcement.

All levels are real implementations in `src/dogfood_v2.gleam`.

---

## Level 1001: Guard clause — basic
**Goal:** Compile match with guard clause and verify Erlang `when` emission.

**Results:** TBD. Run with `gleam run -- level1001`.
**Location:** `src/dogfood_v2.gleam` → `level1001()`

### 1001.1 Guard compilation
```
(lam x (match x ((n (< n 5)) 1) (_ 0)))
```
Expected: Compiles without error. Guard emitted as Erlang `when` clause.

---

## Level 1002: Guard clause — arithmetic
**Goal:** Guard with arithmetic comparison compiles correctly.

### 1002.1 Arithmetic guard
```
(lam x (match x ((n (< n 0)) -1) ((n (> n 0)) 1) (_ 0)))
```
Expected: Compiles, guard conditions on all branches.

---

## Level 1003: Guard clause — struct type
**Goal:** Verify Guard type in AST construction.

### 1003.1 AST Guard type
Construct `ast.Case` with `option.Some(ast.GuardTerm(...))`. Hash and compare.
Expected: Guard variant hashes distinctly from no-guard variant.

---

## Level 1004: Guard clause — hash stability
**Goal:** Guard hashing is deterministic.

### 1004.1 Deterministic hashing
Same guard expression hashed twice produces identical hashes.
Expected: `hash_equal(h1, h2)` is True.

---

## Level 1005: Guard clause — exhaustiveness
**Goal:** All branches reachable with guard conditions.

### 1005.1 Branch coverage
Match with guard that excludes int 5 still hits wildcard.
Expected: Fallback branch covers non-matching values.

---

## Level 1006: `use` expression — basic sugar
**Goal:** `(use x <- f body)` desugars and compiles.

### 1006.1 Use desugaring
```
(use x <- (lam k (k 42)) x)
```
Expected: Evaluates to 42. Lambda-passing desugaring works.

---

## Level 1007: `use` expression — AST roundtrip
**Goal:** Use variant hashes and stores correctly in codebase.

### 1007.1 Use hashing
Construct `ast.Use(...)` term, hash, insert into codebase.
Expected: Successful insertion with hash verification.

---

## Level 1008: `use` expression — chained
**Goal:** Multiple `use` calls compose correctly.

### 1008.1 Chained use
```
(use x <- (lam k (k 10)) (use y <- (lam k (k 20)) (add x y)))
```
Expected: 30.

---

## Level 1009: `use` expression — effect interaction
**Goal:** Use with Do/Handle compiles without conflict.

### 1009.1 Use + effects
Combined use and algebraic effect handler.
Expected: Both desugaring and effect compilation succeed.

---

## Level 1010: `use` expression — type inference
**Goal:** Use expression infers correct type.

### 1010.1 Type inference
```
(use x <- (lam k (k "hello")) x)
```
Expected: Infers Text return type.

---

## Level 1011: Hole — parse and compile
**Goal:** `?` parses to `ast.Hole` and compiles to error.

### 1011.1 Hole compilation
```
(lam x ?)
```
Expected: Compiles to `erlang:error({hole, incomplete_expression})`.

---

## Level 1012: Hole — in codebase
**Goal:** Hole term hashes deterministically.

### 1012.1 Hole hashing
`ast.Hole` hashed, inserted into codebase.
Expected: Verifiable hash, codebase insertion succeeds.

---

## Level 1013: Hole — type inference compatibility
**Goal:** Hole infers as `TypeVar(-1)` without blocking compilation.

### 1013.1 Hole inference
Inference produces fallback type for hole-containing term.
Expected: Does not crash inference engine.

---

## Level 1014: Linearity — basic check
**Goal:** `check_linearity/2` passes for simple continuation term.

### 1014.1 Linearity pass
Term with continuation referenced exactly once passes linearity check.
Expected: `Ok(Nil)`.

---

## Level 1015: Linearity — handler trace
**Goal:** Linearity check walks effect handler structure.

### 1015.1 Handler linearity
Do term with single continuation in handler passes linearity.
Expected: No violation for well-formed handler.

---

## Level 1016: HTTP client — type definitions
**Goal:** `HttpResponse` and `HttpError` types compile.

### 1016.1 Type compilation
Import `gleamunison/http_client`, validate opaque types.
Expected: Module imports and all types resolve.

---

## Level 1017: HTTP client — function signatures
**Goal:** `get`, `post`, `put`, `delete` functions have correct signatures.

### 1017.1 Function arity
All HTTP client functions accept correct argument types.
Expected: Functions compile without signature errors.

---

## Level 1018: JSON — encode types
**Goal:** JSON encoder handles basic Erlang term encoding.

### 1018.1 Encode
Call `json.encode` on integer, string, list.
Expected: Returns `Result(BitArray, BitArray)`.

---

## Level 1019: JSON — decode types
**Goal:** JSON decoder handles basic Erlang term decoding.

### 1019.1 Decode
Call `json.decode` on JSON binary.
Expected: Returns `Result(a, BitArray)`.

---

## Level 1020: JSON — roundtrip
**Goal:** Encode then decode preserves structure.

### 1020.1 Roundtrip
Encode-double-decode produces original structure on simple terms.
Expected: Decoded value matches original.

---

## Level 1021: DateTime — now
**Goal:** `now()` returns non-zero timestamp.

### 1021.1 Now
`datetime.now()` → opaque `DateTime`.
Expected: Timestamp > 1_700_000_000 (2023+).

---

## Level 1022: DateTime — ISO 8601
**Goal:** `now_iso8601()` returns valid ISO 8601 string.

### 1022.1 ISO8601
Check format contains `T` separator and `Z` suffix.
Expected: Valid RFC 3339 format.

---

## Level 1023: DateTime — arithmetic
**Goal:** `add_seconds` and `diff_seconds` are consistent.

### 1023.1 Arithmetic
`diff_seconds(add_seconds(dt, 100), dt) == 100`.
Expected: Arithmetic roundtrip consistent.

---

## Level 1024: DateTime — parse/format
**Goal:** `from_iso8601` then `to_iso8601` preserves format.

### 1024.1 Parse format roundtrip
Parse known ISO string, format back.
Expected: Output matches input (with Z suffix).

---

## Level 1025: Filepath — construction
**Goal:** Opaque `Path` constructed from string.

### 1025.1 From string
`filepath.from_string("/home/user/file.txt")`.
Expected: Path constructed, `is_absolute() == True`.

---

## Level 1026: Filepath — operations
**Goal:** `join`, `parent`, `extension`, `with_extension` work.

### 1026.1 Operations
Chain of filepath operations produces expected results.
Expected: `extension(p)`, `parent(p)`, `join(p, "new")` all correct.

---

## Level 1027: Filepath — edge cases
**Goal:** Edge cases handled: empty path, root, dot segments.

### 1027.1 Edge cases
`from_string("")`, `from_string("/")`, `from_string("./a/b")`.
Expected: All parse without error.

---

## Level 1028: Crypto — hash
**Goal:** SHA256 hash produces 32-byte output.

### 1028.1 SHA256
`crypto.hash(crypto.Sha256, data)`.
Expected: `Result(BitArray, CryptoError)` with 32 bytes.

---

## Level 1029: Crypto — HMAC
**Goal:** HMAC with key produces valid output.

### 1029.1 HMAC
`crypto.hmac(crypto.Sha256, key, data)`.
Expected: Successful computation.

---

## Level 1030: Crypto — random
**Goal:** `random_bytes` produces requested length.

### 1030.1 Random
`crypto.random_bytes(16)`.
Expected: Binary of 16 bytes.

---

## Level 1031: Template — basic interpolation
**Goal:** `{{var}}` replaced with value.

### 1031.1 Interpolation
`template.render("hello {{name}}", [#("name", "World")])`.
Expected: "hello World".

---

## Level 1032: Template — multiple vars
**Goal:** Multiple `{{var}}` patterns interpolated.

### 1032.1 Multiple vars
Three template variables in one string.
Expected: All replaced correctly.

---

## Level 1033: Template — HTML escape
**Goal:** `<`, `>`, `&` characters escaped.

### 1033.1 Escape
Template with special chars in variable values.
Expected: Output has `&lt;`, `&gt;`, `&amp;`.

---

## Level 1034: Logging — levels
**Goal:** `debug`, `info`, `warn`, `error` emit without crash.

### 1034.1 Levels
Call all four log level functions.
Expected: No runtime error, entries in ETS table.

---

## Level 1035: Logging — context
**Goal:** `debug_context` stores context dict.

### 1035.1 Context
Log with context dict containing key-value pairs.
Expected: Context accessible via `/api/logs`.

---

## Level 1036: Config — env load
**Goal:** `config.load()` populates from environment.

### 1036.1 Env load
Load config, verify structure.
Expected: Non-empty env dict.

---

## Level 1037: Config — typed getters
**Goal:** `get_string`, `get_int`, `get_bool` extract values.

### 1037.1 Getters
Config value extraction with type constraints.
Expected: Getters return `Result(value, Nil)`.

---

## Level 1038: Config — precedence
**Goal:** CLI > TOML > env precedence.

### 1038.1 Precedence
Override env value with CLI value via `with_cli`.
Expected: `get` returns CLI value.

---

## Level 1039: Health — run all
**Goal:** `health.run_all()` returns status.

### 1039.1 Run all
Execute default health checks.
Expected: Returns `Healthy(String)` when memory/modules OK.

---

## Level 1040: Health — readiness
**Goal:** `readiness()` returns boolean.

### 1040.1 Readiness
Check if modules loaded.
Expected: `True` when at least one module present.

---

## Level 1041: Metrics — counter
**Goal:** Counter increments and telemetry fires.

### 1041.1 Counter
`metrics.counter("test.counter", 1)`.
Expected: No crash, metric recorded.

---

## Level 1042: Metrics — gauge
**Goal:** Gauge sets and updates.

### 1042.1 Gauge
`metrics.gauge("test.gauge", 42.0)`.
Expected: No crash, value set.

---

## Level 1043: Property — check
**Goal:** `gleamunison_property:check/2` validates property.

### 1043.1 Basic check
Identity property: `fn(x) { x == x }` passes for 100 inputs.
Expected: `{ok, [...]}`.

---

## Level 1044: Property — counterexample
**Goal:** Failing property produces counterexample.

### 1044.1 Counterexample
Property that fails for specific input.
Expected: `{error, #{counterexample => Val, ...}}`.

---

## Level 1045: Trace — capture
**Goal:** Request trace captured to ETS.

### 1045.1 Capture
Call `gleamunison_trace:capture_request/3`.
Expected: Returns `{ok, Id}`.

---

## Level 1046: Trace — list
**Goal:** Captured traces listed.

### 1046.1 List
After capturing, list returns entries.
Expected: List contains captured trace ID.

---

## Level 1047: Trace — get
**Goal:** Individual trace retrievable by ID.

### 1047.1 Get
Lookup trace by returned ID.
Expected: Returns method, path, headers.

---

## Level 1048: CAS adapter — register
**Goal:** Adapter registered and findable.

### 1048.1 Register
Register adapter, find it.
Expected: `{ok, Fun}` on find.

---

## Level 1049: CAS adapter — adapt
**Goal:** Adapter callable through `adapt/2`.

### 1049.1 Adapt
Register and call adapt.
Expected: Returns `{ok, adapted}`.

---

## Level 1050: Full pipeline integration
**Goal:** S-expression with guard + use + hole compiles end-to-end.

### 1050.1 Integration
Parse, elaborate, compile, load expression using new features.
Expected: All pipeline phases succeed without error.

---

## Level 1051 (bonus, in meta): Meta-level verification
**Goal:** Verify all new levels 1001–1050 registered and executable.

### 1051.1 Meta runner
Runner enumerates all levels 1001–1050.
Expected: Each level executes without crashing.
