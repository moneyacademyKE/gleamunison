# Dogfooding Playbook — Levels 1251–1300

Tests covering HTTP server lifecycle, effects runtime deeply, pattern elaboration gaps,
pipeline end-to-end, template edge cases, type pretty printing, metrics histogram,
config error paths, storage deeper (list_refs, zero-byte), sync push + peer status,
compile error paths, labeled functions, lexer string escapes, ability constructs,
and cross-module integration.

All levels are real implementations in `src/dogfood_v7.gleam`.

---

## Level 1251–1253: HTTP Server lifecycle

**Level 1251** — Start server on port 18189.
- **Expected:** Server starts without crash.

**Level 1252** — Start + health check + stop.
- **Expected:** Readiness check passes, server stops cleanly.

**Level 1253** — Restart cycle: start → stop → start → stop.
- **Expected:** No port conflicts, no crashes.

---

## Level 1254–1259: Effects runtime deeply

**Level 1254** — Empty RuntimeConfig: thunk returns 42.
- **Expected:** `effects_run(cfg, fn() { 42 })` returns `Dynamic(42)`.

**Level 1255** — HandlerFrame with single op handler.
- **Expected:** Creates HandlerFrame(ability, dict{0: handler}) without error.

**Level 1256** — Double handler chain (State + IO abilities).
- **Expected:** Thunk runs through both ambient handlers.

**Level 1257** — Multi-op handler (get + set on same ability).
- **Expected:** Dict with 2 op handlers at indices 0 and 1.

**Level 1258** — Chained handlers with different abilities.
- **Expected:** State handler + IO handler chained correctly.

**Level 1259** — Nested RuntimeConfig: outer handler wraps inner run.
- **Expected:** Both inner and outer thunks execute correctly.

---

## Level 1260–1263: Pattern elaboration gaps

**Level 1260** — Elaborate Cons (h:t) and EmptyList patterns.
- **Expected:** Both patterns elaborate to `PatCons` and `PatEmptyList`.

**Level 1261** — Elaborate As-pattern: `(as x (int 42))`.
- **Expected:** Produces `PatAs(Local(n), PatInt(42))`.

**Level 1262** — Nested As+Cons: `(as xs (cons h t))`.
- **Expected:** `PatAs(Local(n), PatCons(Local(n+1), Local(n+2)))`.

**Level 1263** — Elaborate SPText literal pattern.
- **Expected:** Produces `PatText(<<"hello">>)`.

---

## Level 1264–1266: Pipeline end-to-end

**Level 1264** — `compile_definition` → `load_and_eval` full cycle.
- **Expected:** Identity lambda compiles and loads without crash.

**Level 1265** — `parse_string` → `elaborate_only` pipeline.
- **Expected:** `(let x 42 x)` parses and elaborates to a Unit.

**Level 1266** — `parse_string` → `elaborate_only` → `compile_only` 3-stage chain.
- **Expected:** `(lam x x)` runs through all 3 stages producing BEAM bytes.

---

## Level 1267–1268: Template edge cases

**Level 1267** — Multi-variable render: `"hello {{name}}, age {{age}}"`.
- **Expected:** Template renders with both variables substituted.

**Level 1268** — Missing variable: template references `{{name}}` but no vars provided.
- **Expected:** Renders with empty/missing substitution (no crash).

---

## Level 1269–1271: Type pretty printer

**Level 1269** — Pretty print `Int` builtin.
- **Expected:** Returns `"Int"`.

**Level 1270** — Pretty print `Float` builtin.
- **Expected:** Returns `"Float"`.

**Level 1271** — Pretty print function type: `Int Text -> List`.
- **Expected:** Output contains `Int`.

---

## Level 1272: Metrics histogram

**Level 1272** — Record 3 histogram observations.
- **Expected:** `histogram("v7.latency", 12.5)` and more recorded without error.

---

## Level 1273–1275: Config error paths

**Level 1273** — `get_string` for nonexistent key.
- **Expected:** Returns `Error(Nil)`.

**Level 1274** — `get_int` for nonexistent key.
- **Expected:** Returns `Error(Nil)`.

**Level 1275** — CLI override with `with_cli`.
- **Expected:** Overridden key takes precedence over env.

---

## Level 1276–1278: Storage deeper

**Level 1276** — In-memory `list_refs()` returns populated list.
- **Expected:** After insert, `list_refs()` returns refs including the inserted one.

**Level 1277** — DETS `list_refs()` after insert.
- **Expected:** After insert, `list_refs()` returns non-empty list.

**Level 1278** — Insert zero-byte value, roundtrip.
- **Expected:** Lookup returns `Some(<<>>)` with byte_size 0.

---

## Level 1279–1281: Sync push + peer status

**Level 1279** — `push_sync()` with single ref.
- **Expected:** Attempts push (may fail on connect, gracefully handled).

**Level 1280** — PeerStatus variant construction: Connected, Disconnected, Syncing, Failed.
- **Expected:** All 4 variants construct without error.

**Level 1281** — PeerId equality: same name = equal, different name = not equal.
- **Expected:** `PeerId("a") == PeerId("a")` and `PeerId("a") != PeerId("b")`.

---

## Level 1282–1284: Compile error paths

**Level 1282** — Compile `Hole` term.
- **Expected:** Compiles with runtime error emission (hole = incomplete expression).

**Level 1283** — Module name length stability.
- **Expected:** Both short and long input names produce 10-char `m_XXXXXXXX` names.

**Level 1284** — Compile `TypeDef` (Structural declaration).
- **Expected:** Returns BEAM bytes (TypeDef compiles to `ok`).

---

## Level 1285–1287: Labeled functions + guard

**Level 1285** — Elaborate `SLabeledFn([(x, 10), (y, 20)], SVar("x"))`.
- **Expected:** Elaborates to Unit (or produces ElaborateError that doesn't crash).

**Level 1286** — Elaborate `SGuardGuard` as standalone term.
- **Expected:** Returns `Error(UnsupportedTypeRef(...))`.

**Level 1287** — TermDef with guarded match: `(match n ((? 1) 100))`.
- **Expected:** Inserts into codebase successfully.

---

## Level 1288–1291: Lexer string escape sequences

**Level 1288** — Tokenize empty string `""`.
- **Expected:** At least 1 token.

**Level 1289** — Tokenize `"hello\nworld"` (backslash-n escape).
- **Expected:** At least 1 token.

**Level 1290** — Tokenize `"path\\to\\file"` (escaped backslash).
- **Expected:** At least 1 token.

**Level 1291** — Tokenize `"she said \"hello\""` (escaped quote).
- **Expected:** At least 1 token.

---

## Level 1292–1294: Abilities + constructs

**Level 1292** — `Construct(builtin_pair(), [Int(1), Int(2)])`.
- **Expected:** Inserts into codebase successfully.

**Level 1293** — `Use` syntactic sugar: `(use x <- (add) body)` pattern.
- **Expected:** Inserts into codebase successfully.

**Level 1294** — `AbilityDecl` with 2 operations compiles.
- **Expected:** Returns non-empty BEAM bytes with op stubs.

---

## Level 1295–1300: Integration certification

**Level 1295** — Cross-module: HTTP (JSON encode) + Crypto (SHA256 hash) + JSON + Counter + Histogram.
- **Expected:** All 5 modules exercise without crash.

**Level 1296** — Operations + Storage + Pipeline: insert, lookup, config load, health check.
- **Expected:** All modules exercise without crash.

**Level 1297** — Property + Log + Gauge stress: property check, gauge update, log info.
- **Expected:** All 3 modules exercise without crash.

**Level 1298** — Trace + Counter + Health cross: capture 2 traces, counter, health check.
- **Expected:** Traces list returned, counter set, readiness reported.

**Level 1299** — Batch 7 summary.
- **Expected:** Prints 50-level summary.

**Level 1300** — v2.0 full certification: 321 total real dogfood levels, 51 unit tests, 372 total conformance verifications across 9 playbook files.
- **Expected:** Prints final certification banner.
