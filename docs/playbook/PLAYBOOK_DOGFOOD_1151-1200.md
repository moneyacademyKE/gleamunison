# Dogfooding Playbook — Levels 1151–1200

Tests covering loader lifecycle, storage endurance, jets, sync protocol deeply,
concurrency stress, error stress, effect chains, distributed topology, and
full v1.1.0 certification.

All levels are real implementations in `src/dogfood_v5.gleam`.

---

## Level 1151–1155: Loader lifecycle

**Level 1151** — Loader creation: `new_loader()` returns valid loader.
- **Expected:** No crash.

**Level 1152** — Loader with limit: `new_loader_with_limit(50)` returns loader.
- **Expected:** No crash.

**Level 1153** — Loader ensure_loaded: compiles and loads a definition.
- **Expected:** Returns Ok with loaded loader.

**Level 1154** — Loader duplicate load: same definition loaded twice.
- **Expected:** Second `ensure_loaded` succeeds without recompiling.

**Level 1155** — Loader LRU eviction: 4th load with limit 3 evicts 1st.
- **Expected:** First definition is no longer loaded, 4th is loaded.

---

## Level 1156–1160: Storage endurance

**Level 1156** — DETS storage lifecycle: create, insert, close, delete.
- **Expected:** All operations complete cleanly.

**Level 1157** — In-memory storage bulk: 200 inserts.
- **Expected:** Lookup succeeds for the first inserted key.

**Level 1158** — Storage overwrite consistency: 3 inserts same key.
- **Expected:** Lookup returns latest value.

**Level 1159** — Storage missing batch: lookup nonexistent keys.
- **Expected:** Both return errors (not crashes).

**Level 1160** — DETS close and reopen: data persists.
- **Expected:** Reopened DETS has the inserted key.

---

## Level 1161–1163: Jets

**Level 1161** — Jet registry lookup: known hash returns jet code.
- **Expected:** Returns `Some("fun(N) -> gleamunison_jets:fib(N) end")` for hash 123.

**Level 1162** — Jet miss: unknown hash returns None.
- **Expected:** Returns `None`.

**Level 1163** — Jet hash stability: same hash returns same jet.
- **Expected:** Two lookups of identical hash return equal.

---

## Level 1164–1168: Sync protocol deeply

**Level 1164** — Sync state creation.
- **Expected:** No crash.

**Level 1165** — PeerId uniqueness: different names produce unequal values.
- **Expected:** `PeerId("a") != PeerId("b")`.

**Level 1166** — Multi-ref codebase for sync: 20 definitions inserted.
- **Expected:** All 20 inserted, sync state created.

**Level 1167** — Pull sync readiness: codebase + sync state ready.
- **Expected:** No crash.

**Level 1168** — Hash hex for sync ref exchange: 64-char hex string.
- **Expected:** String length = 64.

---

## Level 1169–1174: Concurrency stress

**Level 1169** — High frequency counter: 5000 counter ops.
- **Expected:** All complete.

**Level 1170** — Gauge oscillation: 100 gauge updates.
- **Expected:** All complete.

**Level 1171** — Parallel property batch: 100 property checks.
- **Expected:** All return Ok.

**Level 1172** — Concurrent trace capture: 5 traces.
- **Expected:** All 5 captured.

**Level 1173** — Parallel hash storm: 1000 hash ops.
- **Expected:** All complete.

**Level 1174** — Parallel log storm: 500 log entries.
- **Expected:** All complete.

---

## Level 1175–1179: Error stress

**Level 1175** — Rapid parse error recovery: 4 sequential parses.
- **Expected:** First errors, subsequent recover.

**Level 1176** — Deeply nested match: match inside match body.
- **Expected:** Codebase insert succeeds.

**Level 1177** — Extreme float values: 1e-20 and 1e20.
- **Expected:** Both inserted.

**Level 1178** — Unicode text handling: `"你好世界🌍"`.
- **Expected:** Codebase insert succeeds.

**Level 1179** — Zero-length text: empty binary.
- **Expected:** Codebase insert succeeds.

---

## Level 1180–1184: Effect chains and constructs

**Level 1180** — Do+Handle composition.
- **Expected:** Codebase insert succeeds.

**Level 1181** — Chained effects: nested Handle.
- **Expected:** Codebase insert succeeds.

**Level 1182** — Ref-to self-reference: hash term with RefTo.
- **Expected:** Hash produces 64-char hex.

**Level 1183** — Construct pattern match: `Construct` + `PatConstructor`.
- **Expected:** Codebase insert succeeds.

**Level 1184** — All 15 term variant hashes: cover Int, Float, Text, List, LocalVarRef, RefTo, Lambda, Apply, Let, Match, Do, Handle, Construct, Hole, Use.
- **Expected:** 15 hashes produced.

---

## Level 1185–1189: Distributed topology

**Level 1185** — Process spawn + send builtins.
- **Expected:** All resolve.

**Level 1186** — Timer builtins: sleep, now.
- **Expected:** All resolve.

**Level 1187** — Mnesia adapter ready: table_name path validated.
- **Expected:** No crash.

**Level 1188** — Distributed codebase: 4 definitions inserted.
- **Expected:** All 4 inserted.

**Level 1189** — Node self-identification: self, recv builtins.
- **Expected:** All resolve.

---

## Level 1190–1195: Full integration certification

**Level 1190** — Loader + storage integration.
- **Expected:** Both work without conflict.

**Level 1191** — Jet + codebase integration: insert ref, lookup jet.
- **Expected:** Jet returns None for codebase-inserted ref.

**Level 1192** — Sync + storage integration.
- **Expected:** Both work without conflict.

**Level 1193** — Full module integration: config, filepath, datetime, metrics, prop, trace, log.
- **Expected:** All 8 modules exercise without crash.

**Level 1194** — Pipeline full cycle: parse → hash → load.
- **Expected:** All phases complete.

**Level 1195** — Endurance test: 500 insert+lookup ops.
- **Expected:** All complete.

---

## Level 1196–1200: Final certification

**Level 1196** — All builtins accessible: add, sub, mul, div, json_parse, http_get, file_read.
- **Expected:** All resolve.

**Level 1197** — All storage adapters tested: in-memory, DETS, partitioned DETS, Mnesia.
- **Expected:** All reported.

**Level 1198** — Cross-module integration: JSON, crypto, datetime, filepath, log, metrics, trace.
- **Expected:** All 7 modules exercise without crash.

**Level 1199** — Batch 5 completeness summary.
- **Expected:** Prints 50-level summary.

**Level 1200** — Full v1.1.0 certification: 221 total real dogfood levels, 51 unit tests, 272 total conformance verifications across 7 playbook files.
- **Expected:** Prints final certification banner.
