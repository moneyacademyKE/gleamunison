# Walkthrough — run-by-hash maturity (L0 → L4)

Branch `main`, 2026-10-23. Every block below is real output from a built
escript running **outside the repo**, against a store of its own
(`GLEAMUNISON_STORE_DIR=/tmp/iso`). Nothing was run from the project directory.

Start state: `run <hash>` executed arity-0 definitions only, rendered text only,
had no evidence gate, no store override, no way to retract anything, and no
record of what it had done.

---

## 1. A definition, published and run from a temp directory

```console
$ cp ~/gleamunison/gleamunison_escript /tmp/gleamunison_escript
$ cd /tmp
$ export GLEAMUNISON_STORE_DIR=/tmp/iso GLEAMUNISON_EVIDENCE_SIGNING_KEY=x

$ /tmp/gleamunison_escript test /tmp/iso/prog.glm
1 tests, 0 failed, 1 evidence records attached
evidence: 7f012d9282b6…  test_twice: 1 passed, 0 failed

$ /tmp/gleamunison_escript publish /tmp/iso/prog.glm
published: test_twice  #f816abfabaeb
published: twice  #7f012d9282b6
publish: 2 definitions admitted by evidence
```

`prog.glm` is two lines and lives nowhere near the repo:

```lisp
(define (twice n) (+ n n))
(define (test_twice) (do Test expect (eq? (twice 4) 8)))
```

## 2. Arbitrary arity

A function is a value: the compiler emits exactly `'$eval'/0`, arity-N is a
curried fun, and `run` applies it one argument at a time. The declared type
gives the arity, summed along the curried chain.

```console
$ /tmp/gleamunison_escript run 7f012d9282b6… 21
42
```

Wrong count is refused before any dependency work:

```console
$ /tmp/gleamunison_escript run 7f012d9282b6… 
7f012d9282b6… is a function of arity 1; pass 1 argument(s), or inspect it without calling
$ echo $?
1
```

## 3. Structured output

```console
$ /tmp/gleamunison_escript run --json 7f012d9282b6… 21
{"ref":"7f012d9282b609359c16fe34a918a881ce2bc73087f81e19d2b267e1e6a3881e","value":42}

$ /tmp/gleamunison_escript run --inspect 7f012d9282b6…
{"ref":"7f012d9282b6…","module":"m_e6a3881e","function":{"name":"$eval","export_arity":0,"arity":1}}
```

`--json` always executes and changes only the rendering. `--inspect` is the
sole non-executing mode; it loads the closure to read the export table but
never applies `'$eval'`.

## 4. Exit codes

| Command | Exit | stdout | stderr |
|---|---|---|---|
| `run <hash> 21` | 0 | `42` | empty |
| `run <hash>` (function, no args) | 1 | empty | the arity message |
| `run <zero-hash>` | 2 | empty | `not in the store: 0000…` |
| `run --json <hash> 21` | 0 | one JSON line | empty |
| `run --inspect <hash>` (function) | 0 | one JSON line | empty |
| `run --json <hash>` (function, no args) | 1 | empty | the arity message |

Verified as a block:

```console
$ /tmp/gleamunison_escript run 7f01… 21; echo $?    # 42, then 0
$ /tmp/gleamunison_escript run 7f01…; echo $?       # arity message, then 1
$ /tmp/gleamunison_escript run 0000…; echo $?       # not in the store, then 2
```

## 5. The store's own logs

`log all` merges both logs into one chronological view — admissions and
executions in the order they happened:

```console
$ /tmp/gleamunison_escript log all
2026-10-23T18:25:24Z  content  f816abfabaeb  term
2026-10-23T18:25:24Z  content  7f012d9282b6  term
2026-10-23T18:25:31Z  exec     7f012d9282b6  ok
2026-10-23T18:25:31Z  exec     7f012d9282b6  ok
2026-10-23T18:25:32Z  exec     7f012d9282b6  refused  (… is a function of arity 1; pass 1 argument(s), or inspect it without calling)
2026-10-23T18:25:32Z  exec     000000000000  refused  (not in the store: 0000…)
```

Refusals are recorded, not just successes: the attempt you need to see is the
one that did not happen.

## 6. Retraction refuses rather than half-finishing

`twice` is still called by `test_twice`, so both `purge` and `unpublish` refuse
and name what stands in the way:

```console
$ /tmp/gleamunison_escript purge 7f012d9282b6…
purge: 7f012d9282b6 is used by 1 stored definition(s) outside the removal set: f816abfabaeb
purge: retract or purge those first

$ /tmp/gleamunison_escript unpublish twice
unpublish: twice is used by 1 stored definition(s): f816abfabaeb
unpublish: retract those first, or use `purge` to remove the set
```

In dependency order it succeeds, and the content is gone:

```console
$ /tmp/gleamunison_escript unpublish test_twice
unpublished: test_twice #f816abfabaeb
$ /tmp/gleamunison_escript unpublish twice
unpublished: twice #7f012d9282b6

$ /tmp/gleamunison_escript run 7f012d9282b6… 21; echo $?
not in the store: 7f012d9282b6… (publish it or sync it first)
2
```

The retraction is itself in the log — the last row above is that failed run.

## 7. Verification battery

```console
$ gleam test
593 passed, no failures

$ bb scripts/run_playbook_tests.clj
{:passed 934, :failed 0, :skipped 0, :timed-out 0, :excluded 238}

$ bb scripts/verify_production_boundaries.clj
integrated-gate: PASS        (15/15 gates)
```

---

## What this walkthrough does not claim

- **No expiry.** A definition admitted today runs next year; nothing re-tests it
  between admission and execution.
- **No revocation.** Evidence attaches to a content hash, and the hash does not
  change when the world does.
- **`sync` bypasses admission.** Pulled content enters the store without the
  evidence gate; `run` re-checks the record at execution, which is why that
  second gate exists, but it checks the record and not the claim's current
  truth.
- **Inspection is not execution.** `run --inspect <hash>` on a function loads the
  closure to read its export table and never applies `'$eval'`. `--json` is the
  execution path with a different renderer; a function with no supplied
  arguments is refused by the arity gate.
