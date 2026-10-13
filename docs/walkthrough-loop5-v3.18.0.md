# Loop 5 walkthrough: MCP-over-datalog + package registry (v3.18.0)

Date: 2026-10-13. PR: #7 (merged, CI green). Release: v3.18.0 live on hex.pm.

## Scope

Two headline features from the gaps board:
1. **MCP backed by the datalog engine** (bk-b952, bk-e4dc) — the codebase, queryable as data.
2. **Package registry** (bk-8038, bk-3b6a, bk-4b52) — content-addressed, evidence-gated, serverless.

## What shipped (6 commits)

| Commit | What |
|---|---|
| `c3c15e3` | `codebase_index.gleam`: defs as datalog datoms (def/name, def/hash, def/kind, def/dep per in-corpus reference); scripts evaluate under the native engine |
| `e5e9e06` | **Engine fix**: AVET index `{a→{v→e}}` assumed unique values — shared values silently kept only the last entity. Now `{a→{v→[e]}}` with list-aware insert/remove/lookup/fold. Regression: `test-multi-result-join` |
| `2e71a7c` | MCP tools `callers_of` / `deps_of` / `defs_by_kind` answered by the engine; `ref_hex`/`kind_of` moved to `codebase_index` (import-cycle break, one identity source) |
| `e97ffc8` | `manifest.gleam`: canonical sorted serialization, order-independent hashing, stored under its own content hash, fetch re-hashes and refuses on mismatch |
| `d89cdd6` | `pkg install`: manifest fetch → evidence turnstile per def → namespace commit on the branch. `--peer` syncs first (defs, manifests, evidence all travel as CAS chunks) |
| `cbfa49d` | `pkg publish`: turnstile-gated manifest announce; the printed hash is the package name |

## Verification

- **260/260 tests green** (was 218 at loop 4 close; +42 across index/graph/manifest/pkg/engine-regression).
- Engine AVET regression proven: three entities sharing one value return all three on a join (was: only the last).
- Live registry loop on the real binary: `test lib.lisp` → evidence attached → `pkg publish` → manifest hash `5a1454b6…` → `pkg install <hash>` → `installed double, test_double onto branch main`.
- Hex: `3.18.0` confirmed in the releases API.

## Real bugs found by doing the work

1. **AVET uniqueness assumption** (above) — the engine's own tests never produced two entities sharing a value, so this survived since the engine landed.
2. **Backwards let-threading in my first index generator** — caught by a test timeout, not by reading.
3. **Wrapped list printing** — engine results print across lines; the first extractor read only the last line and silently dropped results.

## Design notes (Hickey stamp)

- The registry is **data, not a service**: a manifest is canonical text hashed into the same DAG that holds code, patches, branches and evidence. Integrity on fetch is structural (re-hash or refuse), not a trusted-server promise.
- The turnstile composes rather than duplicates: `pkg publish` and `pkg install` both call the loop-4 `turnstile.check`; nothing relearns what evidence means.
- Install binds names through the loop-3 namespace: every install is a commit with causal history, so "what came in from package X" is answerable.

## Deferred, honestly

- Manifest `deps` are recorded, not auto-installed (install them first, separately). Transitive resolution is a real feature, not a footnote.
- Selective fetch by hash over sync: v1 `--peer` does a full pull (correct, simple; bandwidth-naive).
- MCP `search_definitions` still ranks via the Gleam hybrid ranker, not the engine's `11_vector.lisp`/`12_bm25.lisp` — one ranker in play at a time; unifying them is a future loop.
- mcp_session.gleam at 459 LOC is near the 500 ceiling; the next feature added there should split it.
