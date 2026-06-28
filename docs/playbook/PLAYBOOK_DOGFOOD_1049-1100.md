# Dogfooding Playbook — Levels 1049–1100

Deep feature tests for HTTP client, JSON edges, DateTime parsing, Filepath edges,
Crypto algorithms, concurrent access patterns, error edge cases, and performance benchmarks.

All levels are real implementations in `src/dogfood_v3.gleam`.

---

## Level 1049–1054: HTTP client

**Level 1049** — FFI module accessibility.
- **Expected:** http_client FFI functions resolve without crash.

**Level 1050** — GET request to unreachable endpoint.
- **Expected:** Returns error, not crash.

**Level 1051** — POST request to unreachable endpoint.
- **Expected:** Returns error, not crash.

**Level 1052** — PUT request to unreachable endpoint.
- **Expected:** Returns error, not crash.

**Level 1053** — DELETE request to unreachable endpoint.
- **Expected:** Returns error, not crash.

**Level 1054** — GET with invalid port number.
- **Expected:** Returns error, not crash.

---

## Level 1055–1060: JSON edge cases

**Level 1055** — Encode string value.
- **Expected:** Produces non-empty binary.

**Level 1056** — Encode boolean value.
- **Expected:** Produces non-empty binary.

**Level 1057** — Encode list value.
- **Expected:** Produces non-empty binary.

**Level 1058** — Encode nested object (Dict).
- **Expected:** Produces non-empty binary.

**Level 1059** — Encode determinism (same input → same output).
- **Expected:** Two encodes of [1,2,3] produce identical binary.

**Level 1060** — Decode invalid JSON.
- **Expected:** Returns error, not crash.

---

## Level 1061–1066: DateTime parsing + formatting

**Level 1061** — now_iso8601 produces valid ISO 8601.
- **Expected:** String length > 15.

**Level 1062** — to_iso8601 on now() produces valid format.
- **Expected:** String length > 15.

**Level 1063** — Parse known ISO 8601 date "2024-01-01T00:00:00Z".
- **Expected:** Successful parse, format matches.

**Level 1064** — Parse invalid date string.
- **Expected:** Returns error.

**Level 1065** — Parse epoch date "1970-01-01T00:00:00Z".
- **Expected:** Successful parse.

**Level 1066** — Negative time diff (add_seconds with -3600).
- **Expected:** diff_seconds returns 3600.

---

## Level 1067–1072: Filepath edge cases

**Level 1067** — Root path "/" is absolute.
- **Expected:** is_absolute returns true.

**Level 1068** — Relative path "a/b/c.txt" is not absolute.
- **Expected:** is_absolute returns false.

**Level 1069** — Parent of "/a/b/c.txt".
- **Expected:** parent() returns path with last segment removed.

**Level 1070** — Join segment to path.
- **Expected:** join produces expected string.

**Level 1071** — Path with dot segments normalizes.
- **Expected:** file_name after normalization.

**Level 1072** — Extension extraction.
- **Expected:** extension from "/a/b/c.txt".

---

## Level 1073–1078: Crypto algorithms + HMAC

**Level 1073** — SHA512 hash produces non-empty output.
- **Expected:** digest byte_size > 0.

**Level 1074** — MD5 hash produces non-empty output.
- **Expected:** digest byte_size > 0.

**Level 1075** — HMAC-SHA256 with random key.
- **Expected:** MAC byte_size = 32.

**Level 1076** — HMAC determinism (same inputs → same output).
- **Expected:** Two MACs are equal.

**Level 1077** — Hash of empty input.
- **Expected:** SHA256 empty digest byte_size = 32.

**Level 1078** — hash_to_hex produces 64-char hex string.
- **Expected:** hex string length = 64.

---

## Level 1079–1084: Concurrent access

**Level 1079** — Counter operations on concurrent keys.
- **Expected:** No crash.

**Level 1080** — Gauge updates on concurrent keys.
- **Expected:** No crash.

**Level 1081** — Parallel JSON encode of different types.
- **Expected:** All succeed.

**Level 1082** — Parallel property checks.
- **Expected:** Both succeed.

**Level 1083** — Concurrent hash operations.
- **Expected:** Both succeed.

**Level 1084** — Concurrent template render.
- **Expected:** Both succeed.

---

## Level 1085–1090: Error edge cases

**Level 1085** — Parse unterminated string.
- **Expected:** Returns parse error.

**Level 1086** — Parse negative integer.
- **Expected:** Parsed or error.

**Level 1087** — Parse large float with many digits.
- **Expected:** Parsed or error.

**Level 1088** — Empty list term insert.
- **Expected:** Codebase insert succeeds.

**Level 1089** — Deeply nested let (5 levels).
- **Expected:** Codebase insert succeeds.

**Level 1090** — Distinct match hashes.
- **Expected:** Two different matches produce different hashes.

---

## Level 1091–1096: Performance benchmarks

**Level 1091** — 5000 insert benchmark.
- **Expected:** Completes, prints elapsed time.

**Level 1092** — Lambda compilation benchmark.
- **Expected:** Completes, prints elapsed time.

**Level 1093** — 3-case match insert benchmark.
- **Expected:** Completes, prints elapsed time.

**Level 1094** — Effect handler insert benchmark.
- **Expected:** Completes, prints elapsed time.

**Level 1095** — 5-hash throughput.
- **Expected:** Completes, prints elapsed time.

**Level 1096** — 5-log throughput.
- **Expected:** Completes, prints elapsed time.

---

## Level 1097–1100: End-to-end integration

**Level 1097** — Full pipeline: guard + hole + use + handle + lambda.
- **Expected:** All variants combine into one unit, codebase insert succeeds.

**Level 1098** — Stdlib + ops integration: config, health, datetime, filepath, log, counter.
- **Expected:** All modules exercise without crash.

**Level 1099** — Trace + adapter integration: capture trace, list traces, register adapter, adapt.
- **Expected:** Trace captured, adapter registered and called.

**Level 1100** — v1.1.0 certification: prints 50-level summary.
- **Expected:** Prints all 9 domain summaries.
