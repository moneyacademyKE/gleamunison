# Loop 6 walkthrough: monadic bindings + full span coverage (v3.19.0)

Merged as PR #8 (`db98200`), published to hex.pm as v3.19.0, tag `v3.19.0`.
Beads: bk-be7b (monadic bindings), bk-b748 (span coverage). Both closed.

## Scope

Items 3 and 4 from the post-loop-5 board:

1. **Monadic syntax bindings** (Phase 7.7, was PENDING → DONE).
2. **Term-level spans, deeper**: wrap every parser form, kill `(0,0)` spans.

## What shipped

### Monadic bindings (`e11ecae`)

Parser-only desugar, zero elaborator/compiler changes:

- `(let* ((x e1) (y e2) ...) body)` → nested `SLet`. Pure sequencing.
- `(chain ((x e1) (y e2) ...) body)` → nested `SUse`. Monadic bind: each
  computation receives the rest of the chain as its continuation. This works
  because `ast.Use` compiles to `(call)(fun(x) -> body end)` — nested `use`
  is do-notation for continuation-passing computations.
- Wrong-arity `let*`/`chain` forms raise a parse error instead of silently
  falling through to application (caught by the red test).

Live smoke (REPL):

```
(define bind-int (lam v (lam k (k v))))
(define answer (chain ((x (bind-int 20)) (y (bind-int 22))) (+ x y)))
answer   ; → 42 : Int
(define v (let* ((x 20) (y 22)) (+ x y)))
v        ; → 42 : Int
```

### Span coverage (`62880c2`)

- All term forms wrapped in `SLoc`: `let`, `lam`, `fn*`, `if`, `match`, `use`.
  Innermost-span-wins (loop 3) means subterm errors keep their own positions;
  form-level errors now cite the form.
- `ParseError(0,0)` eliminated for: invalid match case, invalid use binder,
  invalid pattern, invalid labeled parameter, `fn*` param list, and the new
  `let*`/`chain` binding pairs. `Empty input` keeps `(0,0)` — no input has no
  position.
- Live smoke: `(define broken (match x 42))` → `Invalid match case at line 1,
  col 25` (the actual case position; was `(0,0)`).

**Deliberately NOT wrapped:** `define`/`type`/`list` meta-forms. Eight call
sites across six modules (repl, verify, lsp, lsp_features, mcp_session,
cli_datalog) pattern-match the bare `SList([SVar("define"), ...])` shape.
Wrapping them would silently break top-level definition handling everywhere.
They are not terms and never reach `elaborate_term`; the wrap would buy
nothing. This is the Hickey call of the loop: cover the term language, leave
the meta language alone.

## Verification

- `gleam test`: **281/281 green** (260 before the loop; +21 new tests).
- `gleam format --check src test`: clean (one CI failure on an unformatted
  wrap, fixed by running the formatter).
- Birdie snapshot reviewed before accepting: the diff was exactly the three
  expected `SLoc` wrappers with correct columns (1, 10, 19).
- CI green, PR #8 merged, hex verified live (releases API shows 3.19.0).

## Design notes

- Phase 7.7 said "desugar to nested lambdas during elaboration." The shipped
  version desugars at *parse* time to `SUse`, which elaborates to `ast.Use`,
  which compiles to nested lambdas. Same destination, earlier death for the
  sugar: everything downstream (elaboration, hashing, compilation) sees only
  the forms it already knows.
- `chain` + abilities is where this gets interesting next: an ability whose
  handler invokes its continuation gives you monadic do-notation over
  effects with machinery that already exists.

## Deferred

- `use`-style multi-pair extension to the existing `use` keyword (rejected:
  parser ambiguity vs. the two existing `use` shapes; `chain` is explicit).
