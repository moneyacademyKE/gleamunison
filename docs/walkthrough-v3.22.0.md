# Loop 8 walkthrough: crash-on-bad-input

v3.22.0, live on hex.pm. PR #12 merged green. 337/337 tests.

## What the dogfood found

The deepseek game died on EOF. `read_line` returns an empty string, `string->int` called `binary_to_integer` on it, and the process raised `badarg`. A builtin that parses user text must return a value, not kill the caller.

## The fix

`string->int` now returns `{left, N}` on success and `{right, bad_integer}` on garbage, including the empty string. Three regression tests cover success, garbage, and empty.

## The bug behind the bug

Fixing the crash exposed a second one. `(left 7)` built `{left, 7}`, an atom tuple. A `(left n)` pattern compiled to `{m_<sha256("left")>, n}`, a module tuple. The two shapes never unified, so matching on `left` or `right` crashed with `case_clause` every time. Nobody had written that match before, so the suite never saw it.

Constructors now emit the tuple the pattern matches. `(match (left 7) ((left n) n))` returns 7. Verified live.

## What I tried and reverted

`div`, `mod`, and `string-slice` raise on bad input too. I wrapped them the same way. The datalog engine suite went red: it uses `div` as a value, and wrapping the success broke every caller. Reverted. Arithmetic stays crash-on-bad. Parsing user text is the one that must not.

## Live proof

The deepseek game, replayed with a guess then EOF: "Too low!" then "bye!". Before this release that EOF was a crash dump.

## Gates

337 passed, 0 failed. CI green after one format fix. Tag v3.22.0 pushed. hex.pm releases API shows 3.22.0.
