# Monadic do-notation: `chain` + continuation handlers

`chain` is do-notation for gleamunison. It needs no runtime machinery beyond
what `use` already compiles to:

    (use x m rest)  ≡  m(fun(x) -> rest end)

A handler is any function that receives the continuation and decides what to
do with it: invoke it (State, Maybe-Just), skip it (Maybe-Nothing), invoke it
twice (nondeterminism), or stash it (coroutines).

## The idiom

```lisp
(define (state-get k) (lam (s) ((k s) s)))
(define (state-put new) (lam (k) (lam (s) ((k 0) new))))
(define (state-returns v) (lam (s) v))
(define (run-state m s0) (m s0))

(define prog
  (chain ((a state-get)
          (_ (state-put (add a 1)))
          (b state-get))
    (state-returns b)))

(run-state prog 10)   ; => 11
```

## The one rule: the body is a monadic value

`chain ((x m) ...) body` desugars to nested `use`, so `body` sits inside the
innermost continuation. It must therefore be a *monadic value*, not a raw
one. Each monad spells its `return` explicitly:

| Monad | body looks like |
|---|---|
| State | `(state-returns value)` |
| Maybe | `(just value)` / `nothing` |

Monad-agnostic desugaring cannot inject `return` — it is a different function
per monad. Explicit is honest: you always see exactly which monad you're in.

## Maybe with short-circuit

```lisp
(define (just v) (lam (j) (lam (n) (j v))))
(define nothing (lam (j) (lam (n) n)))
(define (maybe-bind m) (lam (k) ((m (lam (v) (k v))) nothing)))
(define (from-maybe default m) ((m (lam (v) v)) default))

(define prog
  (chain ((a (maybe-bind (just 20)))
          (b (maybe-bind nothing))     ; <- chain dies here
          (c (maybe-bind (just 2))))
    (just (add a c))))

(from-maybe 0 prog)   ; => 0
```

`maybe-bind` invokes its continuation only on `just`. On `nothing` the rest
of the chain never runs — the handler simply doesn't call `k`.

## Function sugar

Standard lisp define/lambda sugar keeps handlers readable:

```lisp
(define (f x y) body)   ==   (define f (lam x (lam y body)))
(lam (x y) body)        ==   (lam x (lam y body))
```

Both desugar at parse time to the curried form; content hashes are identical
(proven in `test/define_sugar_test.gleam`).
