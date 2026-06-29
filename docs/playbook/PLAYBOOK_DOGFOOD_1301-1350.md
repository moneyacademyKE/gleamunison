# Dogfooding Playbook — Levels 1301–1350

Integration tests covering HTTP client against live server, parser special forms,
config precedence chain, health check variants, datetime deep edges, filepath edges,
inference error paths, elaboration gaps (TypeAlias, SRef, empty unit, PubTypeAlias),
codebase insert_raw/multi-def/AbilityDecl, lower TFun error, jet miss, partitioned
DETS lifecycle, and cross-module certification.

All levels are real implementations in `src/dogfood_v8.gleam`.

---

## Level 1301–1306: HTTP client integration

**Level 1301** — GET /api/health against running server.
- **Expected:** HTTP 200 response, no crash.

**Level 1302** — POST /api/eval?expr=42 against running server.
- **Expected:** HTTP response, no crash.

**Level 1303** — PUT /api/eval?expr=99 against running server.
- **Expected:** HTTP response, no crash.

**Level 1304** — DELETE /api/health against running server.
- **Expected:** HTTP response (may be 405), no crash.

**Level 1305** — GET to dead port (63999).
- **Expected:** `Error(HttpError(_))` connection refused.

**Level 1306** — GET /api/status route.
- **Expected:** HTTP response from status endpoint.

---

## Level 1307–1314: Parser special forms

**Level 1307** — Parse `(if 1 2 3)` — 3-arg if form.
- **Expected:** Desugars to `SMatch(c1, [SCase(SPInt(1), None, c2), SCase(SPVar("_"), None, c3)])`.

**Level 1308** — Parse `(match 42 (1 ? 100) (_ 200))` — match with guard.
- **Expected:** Case has `guard: Some(_)`.

**Level 1309** — Parse `(use (x rest) (fn) body)` — use with rest binder.
- **Expected:** Desugars to `SLet(name, rest, SUse(name, call, body))`.

**Level 1310** — Parse `'hello` — quoted atom.
- **Expected:** Parses to `SList([SVar("quote"), SVar("hello")])`.

**Level 1311** — Parse `'42` — quoted integer.
- **Expected:** Parses to `(quote 42)`.

**Level 1312** — Parse `(define foo 42)` — define special form.
- **Expected:** Returns `SList([SVar("define"), SVar("foo"), SInt(42)])`.

**Level 1313** — Parse empty string `""`.
- **Expected:** Returns `Error(ParseError("Empty input", 0, 0))`.

**Level 1314** — Parse with extra tokens `"42 43"`.
- **Expected:** Returns `Error(ParseError("Extra tokens after expression", ...))`.

---

## Level 1315–1317: Config deeper

**Level 1315** — `get_bool` for nonexistent key.
- **Expected:** Returns `Error(Nil)`.

**Level 1316** — `get_bool` from CLI override with `BoolVal(True)`.
- **Expected:** Returns `Ok(True)`.

**Level 1317** — Full precedence chain: cli > toml > env.
- **Expected:** TOML layer populated manually, then CLI override takes precedence over TOML.

---

## Level 1318–1320: Health deeper

**Level 1318** — `run_checks` with custom always-passing check.
- **Expected:** Returns `Healthy(_)`.

**Level 1319** — `run_checks` with empty check list.
- **Expected:** Returns `Healthy(_)` with node info.

**Level 1320** — `run_checks` with always-failing check.
- **Expected:** Returns `Unhealthy(_)` with check name in message.

---

## Level 1321–1324: Datetime deeper

**Level 1321** — `from_iso8601("this-is-not-a-date")`.
- **Expected:** Returns `Error(ParseError(_))`.

**Level 1322** — Negative diff: add -7200 seconds, diff back = 7200.
- **Expected:** `diff_seconds(dt, earlier)` = 7200.

**Level 1323** — Zero delta: add 0 seconds, diff = 0.
- **Expected:** `diff_seconds(same, dt)` = 0.

**Level 1324** — ISO8601 roundtrip: `to_iso8601` → `from_iso8601` → `to_iso8601` = original.
- **Expected:** Strings match exactly.

---

## Level 1325–1329: Filepath deeper

**Level 1325** — Chained joins: `root() |> join("usr") |> join("local") |> join("bin")`.
- **Expected:** `to_string` returns `"/usr/local/bin"`.

**Level 1326** — `parent(root())`.
- **Expected:** Returns `Path([], True)`.

**Level 1327** — `to_string(root())`.
- **Expected:** Returns `"/"`.

**Level 1328** — Multi-dot extension: `archive.tar.gz`.
- **Expected:** `extension` returns `"gz"`.

**Level 1329** — Join with empty string.
- **Expected:** Original path unchanged.

---

## Level 1330–1333: Inference error paths

**Level 1330** — Heterogeneous list `[Int(1), Text("two")]`.
- **Expected:** Returns `Error(TypeMismatch(_, _, "element mismatch"))`.

**Level 1331** — Do with op index 999 (out of bounds) on ability with 1 op.
- **Expected:** Returns `Error(TypeMismatch(_, _, "op index out of bounds"))`.

**Level 1332** — Apply `Int(42)` as function to `Int(1)`.
- **Expected:** Returns `Error(TypeMismatch(_, _, "not a function"))`.

**Level 1333** — `check_linearity` on identity lambda.
- **Expected:** Returns `Ok(Nil)`.

---

## Level 1334–1337: Elaboration deeper

**Level 1334** — `SurfaceTypeAlias("MyInt", TBuiltin(TInt))`.
- **Expected:** Elaborates to `Unit` with a `TypeDef(Structural(...))`.

**Level 1335** — `SRef(ref)` elaborated to `RefTo(ref)`.
- **Expected:** Produces `ast.RefTo(_)`.

**Level 1336** — `SurfaceUnit` with empty defs list.
- **Expected:** Elaborates to `Unit(_, [])`.

**Level 1337** — `SurfacePubTypeAlias("MyText", TBuiltin(TText))`.
- **Expected:** Elaborates identically to TypeAlias (dummy `Structural`).

---

## Level 1338–1340: Codebase deeper

**Level 1338** — `insert_raw(cb, ref, raw_bytes)`.
- **Expected:** Ref appears in adapter lookup.

**Level 1339** — `insert` with multi-def unit (TermDef + TypeDef).
- **Expected:** Both refs appear in adapter lookups.

**Level 1340** — `insert` with AbilityDecl def.
- **Expected:** Inserts without error.

---

## Level 1341–1344: Lower + Jets + Pipeline

**Level 1341** — `lower_type_ref(TFun([], TVar("x")), dict.new())`.
- **Expected:** Returns `Error(UnsupportedTypeRef("TFun not supported"))`.

**Level 1342** — `get_jet` with non-jet (random hash).
- **Expected:** Returns `None`.

**Level 1343** — `get_jet` with fib jet hash (123 in 256-bit).
- **Expected:** Returns `Some("fun(N) -> gleamunison_jets:fib(N) end")`.

**Level 1344** — `parse_only("{no}")` — invalid syntax.
- **Expected:** Returns parse error.

---

## Level 1345–1347: Storage partitioned DETS

**Level 1345** — Partitioned DETS lifecycle: create → insert → lookup → close → delete.
- **Expected:** Data roundtrips correctly.

**Level 1346** — Partitioned DETS `list_refs` after 2 inserts.
- **Expected:** `list_refs` returns non-empty list.

**Level 1347** — Partitioned DETS reopen: close → reopen → data still there.
- **Expected:** Lookup after reopen returns the original data.

---

## Level 1348–1350: Integration certification

**Level 1348** — Full module exercise: JSON + Crypto + Counter + Histogram + DateTime + Filepath + Log.
- **Expected:** All 8 modules exercise without crash.

**Level 1349** — Batch 8 summary.
- **Expected:** Prints 50-level summary.

**Level 1350** — v2.0 full certification: 371 total real dogfood levels, 51 unit tests, 422 total conformance verifications across 10 playbook files.
- **Expected:** Prints final certification banner.
