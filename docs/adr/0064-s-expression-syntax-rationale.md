# ADR-0064: Why S-Expressions — the Syntax Choice, Its Costs, and the Escape Hatch

## Context

gleamunison's surface syntax is a Lisp: every construct is `(head args…)`,
parsed to a minimal s-expression tree before elaboration. The question
"why Lisp, and is there something more powerful?" has now been asked often
enough — by the owner, and implicitly by every prospective contributor — that
the reasoning belongs in a durable record instead of chat history.

The core observation framing everything below: gleamunison's identity system
is content-addressed. A definition is the hash of its elaborated term in a
Merkle DAG; the name is a pointer and the source text is a rendering. That
makes syntax the cheapest layer of the whole system — a claim that must be
weighed honestly, because it cuts both ways.

## Decision

Keep s-expressions as the canonical surface syntax. Do not treat notation as
settled forever: the hash makes syntax disposable, and a second front-end is
an additive move, not a rewrite (see Alternatives).

## Why Lisp — the upsides

1. **The parser is tiny and total.** No precedence, no associativity, no
   whitespace significance, nothing to argue about. This is why the formatter
   (`gleam run -- fmt`) shipped as one rule with zero configuration, and why
   it is provably idempotent.
2. **Code is data.** Every desugar shipped so far (`let*`, `chain`, the
   `(define (f x) b)` function sugar) was a parser-local list rewrite with no
   elaborator or compiler changes. Desugaring is a pure function over lists.
3. **Agents write it flawlessly.** Uniform shape plus balanced parens is
   exactly what token predictors are best at. In the live dogfood
   (qwen3.8-max, 2026-10-14), the model produced valid gleamunison on the
   first attempt with zero syntax errors. Structure errors are *loud*
   (unbalanced parens fail the parse) instead of *silent* (a wrong indent in
   a whitespace language still parses — it just means something different).
4. **The hash proves notation is disposable.** `(define (f x) b)` and the
   explicit curried spelling elaborate to the same term and hash identically
   (proven in `test/define_sugar_test.gleam`). Same definition, different
   text. No other layer of the system offers that guarantee.

## The honest costs

1. **No zero-arg call syntax.** `(f)` is just `f` — "reference the function"
   and "call it with no arguments" are indistinguishable. This produced a
   real bug: `read_line` returned a thunk nothing could force, crashing the
   number-guessing game until the builtin was made eager (commit `08dd866`).
   Every other 0-arity builtin already evaluated eagerly; the convention now
   is that 0-arity builtins must evaluate at the reference site.
2. **Math reads backwards.** `(add (mul x 2) 1)` instead of `x * 2 + 1`.
   Fine for logic, hostile for arithmetic-heavy code.
3. **No visual landmarks.** Every form is the same shape; structure is
   carried by indentation alone. This is why the formatter is load-bearing
   rather than optional.
4. **Errors need explicit plumbing.** Uniform shape means positions are not
   free from the grammar — spans had to be threaded through the parser and
   elaborator deliberately (loop 6) to get line/col diagnostics at all.
5. **Onboarding tax.** Nobody's first language is Lisp. Mitigated with sugar
   and docs, never eliminated.

These are notation complaints, not semantic ones — and notation is the
cheapest layer to change.

## Why not an existing language

**Gleam is the implementation language, not the surface.** The compiler and
toolchain are written in it, but as the user-facing language it is the wrong
shape: (1) no content addressing — a Gleam definition is text in a file, and
retrofitting hash-identity means rebuilding its parser, resolver, and
compiler, i.e. a new language wearing Gleam's clothes; (2) ambient IO — any
Gleam function can perform IO silently, while our capabilities, transcripts,
replay, and publish turnstile all require effects to be the *only* boundary;
(3) a fixed, full-size grammar — we need a reader this small so notation
stays swappable.

**Clojure is the tempting one and the wrong one.** It is homoiconic and
data-first, but: dynamically typed (no HM inference, no type-error call sites
for agents to self-repair on), identity is mutable vars in namespaces (a
`def` redefines — no immutable DAG, no hash-keyed definitions), and it runs
on the JVM while our distribution story is OTP. Clojure with our semantics
bolted on would be a fork, not Clojure.

Gleam and Clojure answer "what should programs look like." gleamunison
answers "what should a definition *be*" — and both already answered that with
"text" and "a var." Wrong answers for what this is for.

## Alternatives considered (front-ends over the same AST and hashes)

All seven are notations; the hash makes them equivalent. Ranked by agent fit:

1. **S-expressions (chosen).** Zero grammar to get wrong, loud errors,
   code-as-data. Best for agents, acceptable for humans with sugar.
2. **ML/Gleam-style infix** (`let x = f(y) |> g`). Best for humans; costs a
   real grammar with precedence. The leading candidate for a second
   front-end.
3. **Prolog-style clauses.** We ship a datalog engine already, so a logic
   front-end is half-built. Great for rules, awful for sequencing IO.
4. **Smalltalk keyword messages** (`guess between: low and: high`). Readable
   as prose, still uniform. The sweet spot nobody builds on.
5. **Forth/concatenative.** Best structural fit (point-free composition
   mirrors de Bruijn internals); readable by almost no one.
6. **Elixir-style** (`def f(x), do: ... end`). Thematically cute on BEAM;
   full expression grammar, same complexity as ML with less payoff.
7. **Indentation/YAML-style.** Pretty to read; whitespace is invisible to
   both LLMs and diff tools. Models mangle it. Rejected.
8. **M-expressions.** Historical footnote — the syntax Lisp was designed to
   have in 1958, proving the notation layer was always meant to be swappable.

The likely end-state: agents write parens, humans read an ML front-end, and
the DAG cannot tell the difference — `x * 2 + 1` and `(add (mul x 2) 1)`
hashing to the same definition is the acceptance test.

## Consequences

- The parens stay canonical until a second front-end proves hash-equivalence
  the way the define-sugar did.
- Any new front-end must target the existing surface AST and pass the same
  elaborated-hash equality proof. A front-end that changes semantics is a
  different language and is out of scope.
- The zero-arg convention (0-arity builtins evaluate eagerly at the reference
  site) is the standing workaround for the one genuine semantic wart s-exprs
  created.
