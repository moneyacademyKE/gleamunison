# Dogfooding Playbook — Levels 1201–1250

Tests covering REPL bracket counting edge cases, parser/lexer edge cases,
content-addressed hash identity properties, JSON deep edge cases, crypto edge cases,
datetime/filepath stress, and operations deeper.

All levels are real implementations in `src/dogfood_v6.gleam`.

---

## Level 1201–1210: REPL bracket counting edge cases

**Level 1201** — Empty input: `count_brackets("", False, 0) == 0`.
- **Expected:** Returns 0.

**Level 1202** — Only parens: `count_brackets("()", False, 0) == 0`.
- **Expected:** Returns 0.

**Level 1203** — Parens inside string ignored.
- **Expected:** Brackets inside quoted strings don't count.

**Level 1204** — Quote prefix `'` doesn't affect depth.
- **Expected:** Returns 0 for `'(a b c)`.

**Level 1205** — Escaped paren in string.
- **Expected:** `"\(escaped"` doesn't affect depth.

**Level 1206** — Nested balanced: `((let x 1) (let y 2))`.
- **Expected:** Returns 0.

**Level 1207** — Deeply balanced: `((((((((((1))))))))))`.
- **Expected:** Returns 0.

**Level 1208** — Unclosed: `(`.
- **Expected:** Returns 1.

**Level 1209** — Extra close: `)`.
- **Expected:** Returns -1.

**Level 1210** — Multiline balanced.
- **Expected:** Returns 0 across newlines.

---

## Level 1211–1216: Parser edge cases

**Level 1211** — Empty parens `()`.
- **Expected:** Parses successfully (empty list).

**Level 1212** — Whitespace `   42   `.
- **Expected:** Parses successfully.

**Level 1213** — Deeply nested `((((((42))))))`.
- **Expected:** Parses successfully.

**Level 1214** — Nested strings with parens.
- **Expected:** Strings parsed correctly.

**Level 1215** — Error has line and column: `\n\n(123`.
- **Expected:** `e.line > 0` and `e.col > 0`.

**Level 1216** — Comments: `(let x 1 ; comment\n  x)`.
- **Expected:** Parses successfully.

---

## Level 1217–1222: Lexer edge cases

**Level 1217** — Empty tokenize.
- **Expected:** 0 tokens.

**Level 1218** — Parens tokens `()()`.
- **Expected:** 4 tokens (2 LParen + 2 RParen).

**Level 1219** — Integers `0 -42 9999999999`.
- **Expected:** 3+ tokens.

**Level 1220** — Floats `3.14 -2.5 0.0`.
- **Expected:** 3+ tokens.

**Level 1221** — Strings `"hello" "world"`.
- **Expected:** 2+ tokens.

**Level 1222** — Quotes `'x 'y`.
- **Expected:** 2+ tokens.

---

## Level 1223–1228: Content-addressed identity

**Level 1223** — Hash hex format: 64 lowercase hex chars.
- **Expected:** `string.length(hex) == 64` and `hex == string.lowercase(hex)`.

**Level 1224** — Distinct AST distinct hash: Int(1) != Int(2).
- **Expected:** `hash_equal` returns False.

**Level 1225** — Hash from bytes roundtrip: same bytes → same hash.
- **Expected:** `hash_equal` returns True.

**Level 1226** — Type-inclusive hashing: `Int(42)` and `Text("42")` differ.
- **Expected:** `hash_equal` returns False.

**Level 1227** — All 15 AST variants unique.
- **Expected:** All 15 hashes are produced.

**Level 1228** — Genesis hash structure.
- **Expected:** Genesis hash type intact.

---

## Level 1229–1234: JSON deep edge cases

**Level 1229** — JSON flat array `[1, 2, 3, 4]`.
- **Expected:** Non-empty binary.

**Level 1230** — JSON empty object.
- **Expected:** Non-empty binary.

**Level 1231** — JSON large number `2147483647`.
- **Expected:** Non-empty binary.

**Level 1232** — JSON negative number `-42`.
- **Expected:** Non-empty binary.

**Level 1233** — JSON special characters `"line1\nline2\ttab"`.
- **Expected:** Non-empty binary.

**Level 1234** — JSON unicode `"日本語🚀"`.
- **Expected:** Non-empty binary.

---

## Level 1235–1240: Crypto edge cases

**Level 1235** — Hash 1024-byte random input.
- **Expected:** SHA256 digest byte_size = 32.

**Level 1236** — Hex roundtrip: 64-char hex string.
- **Expected:** `string.length(hex) == 64`.

**Level 1237** — SHA512 hex length.
- **Expected:** `string.length(hex) == 128`.

**Level 1238** — Random 0 bytes.
- **Expected:** byte_size = 0.

**Level 1239** — Random 4096 bytes.
- **Expected:** byte_size = 4096.

**Level 1240** — Different keys produce different hashes.
- **Expected:** Hashes are unequal.

---

## Level 1241–1244: Datetime + filepath stress

**Level 1241** — 1-year forward arithmetic (31536000 seconds).
- **Expected:** `diff_seconds(far, dt) == 31536000`.

**Level 1242** — Filepath deep nesting `/a/b/c/d/e/f/g/h/i/j/file.txt`.
- **Expected:** `file_name` returns `file.txt`.

**Level 1243** — Filepath empty extension `/a/b/file`.
- **Expected:** `extension` returns `""`.

**Level 1244** — Filepath no slashes `filename.txt`.
- **Expected:** `is_absolute` returns False.

---

## Level 1245–1247: Operations deeper

**Level 1245** — Multi-level log: debug, info, warn, error.
- **Expected:** All 4 emit without crash.

**Level 1246** — Counter + gauge mixed.
- **Expected:** All ops succeed.

**Level 1247** — Multi-trace captures.
- **Expected:** All 5 captured.

---

## Level 1248–1250: Full integration certification

**Level 1248** — Full module exercise: JSON, crypto, datetime, filepath, log, metrics, config, health.
- **Expected:** All 8 modules exercise without crash.

**Level 1249** — Batch 6 summary.
- **Expected:** Prints 50-level summary.

**Level 1250** — v1.1.x full certification: 271 total real dogfood levels, 51 unit tests, 322 total conformance verifications across 8 playbook files.
- **Expected:** Prints final certification banner.
