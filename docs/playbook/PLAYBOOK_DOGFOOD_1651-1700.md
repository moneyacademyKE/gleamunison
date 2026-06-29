# Dogfooding Playbook — Levels 1651–1700

The final gap-filling batch. All 20 previously-untested modules are now exercised. Every public API in the gleamunison runtime has at least one conformance verification.

---

## CRITICAL: crypto.gleam (0→6 conformance)

**Level 1651** — `crypto.hash(Sha256, "hello")` → 32-byte digest
**Level 1652** — `crypto.hash(Sha512, "test data")` → 64-byte digest
**Level 1653** — `crypto.hash(Md5, "md5 test")` → 16-byte digest
**Level 1654** — `crypto.hmac(Sha256, key, msg)` → digest
**Level 1655** — `crypto.random_bytes(32)` → 32 random bytes
**Level 1656** — `crypto.hash_hex(Sha256, data)` → hex string

## CRITICAL: json.gleam (0→2 conformance)

**Level 1657** — `json.encode(42)` → binary
**Level 1658** — `json.encode("hello world")` → `json.decode` → roundtrip

## CRITICAL: metrics.gleam (0→3 conformance)

**Level 1659** — `metrics.counter` multiple increments
**Level 1660** — `metrics.gauge` multiple values
**Level 1661** — `metrics.histogram` 4 observations

## HIGH: http_client.gleam (3→6 conformance)

**Level 1662** — `http_client.post` against nonexistent server
**Level 1663** — `http_client.put` against nonexistent server
**Level 1664** — `http_client.delete` against nonexistent server

## HIGH: log.gleam (5→8 conformance)

**Level 1665** — `log.debug_context` with context dict
**Level 1666** — `log.warn_context` with context dict
**Level 1667** — `log.error_context` with context dict

## MEDIUM: filepath, identity, datetime, pipeline

**Level 1668** — `filepath.has_extension` on 4 paths
**Level 1669** — `identity.hash_bytes` exercised
**Level 1670** — `identity.hash_to_short_string` 12-char truncation
**Level 1671** — `datetime.now()` → `to_iso8601` opaque roundtrip
**Level 1672** — `pipeline.parse_only("42")`
**Level 1673** — `pipeline.ref_for_name`

## LOW: lower, elaborate, compile, repl, inference, types, lexer, parser

**Level 1674** — `lower_type_ref(TFun(...))` → `UnsupportedTypeRef` error
**Level 1675** — `elaborate_unit` with `SurfaceTypeAlias`
**Level 1676** — `elaborate_unit` with `SurfacePubTypeAlias`
**Level 1677** — `compile_definition` on Hole term (emits `erlang:error`)
**Level 1678** — `eval_string("undefined_var_x")` → error
**Level 1679** — `infer_term(Construct(ref, [Int(1)]))` cache miss
**Level 1680** — `infer_term(Match(..., []))` empty cases
**Level 1681** — `check_linearity(Lambda(...))`
**Level 1682** — `Do` with `CTTerm` (not `CTAbility`) cache entry
**Level 1683** — `parse_string("")` empty input
**Level 1684** — `parse_string("\"hello")` unterminated string
**Level 1685** — `parse_string("\"\\t\\n\\r\\\"\\\\\"")` complex escapes
**Level 1686** — `parse_string("42 99")` extra tokens
**Level 1687** — `parse_string("(MyConstructor a b c)")` 3-arg constructor

## INTEGRATION: Cross-module chains

**Level 1688** — crypto+json: hash → encode size
**Level 1689** — metrics+log: counter + info_context
**Level 1690** — filepath chain: join → has_extension → file_name → extension → parent
**Level 1691** — pipeline: parse_only → elaborate_only
**Level 1692** — lower: TBuiltin(TInt) → type_ref_to_type
**Level 1693** — identity+crypto: hash_bytes → hash_to_short_string + crypto hash
**Level 1694** — http_client+log+metrics: GET with success/error counters
**Level 1695** — loader+codebase+storage: insert → ensure_loaded → is_loaded
**Level 1696** — eval_string("(add 10 20)") → result
**Level 1697** — datetime+identity: now ISO8601 → hash
**Level 1698** — compile simple int def
**Level 1699** — list_all_match: [Int(1), Int(2)] all IntType
**Level 1700** — Batch 15 certification banner
