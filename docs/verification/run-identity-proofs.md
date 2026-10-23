# Run-by-hash identity proofs — 2026-10-23

What `gleamunison run <hash>` guarantees, and the command or test that proves
each claim. Branch `main`. Every row below is re-runnable; nothing here is a
claim about intent.

Scope: the store-execution path (`src/gleamunison/run_ref.gleam`,
`src/gleamunison/cli_run.gleam`, `src/gleamunison/cli_lifecycle.gleam`,
`src/gleamunison/cli_output.gleam`, `src/gleamunison/codebase.gleam`).

---

## 1. Identity proof — the hash is re-verified on read

A definition is stored under `sha256` of its content. `codebase.get` re-hashes
what it reads and refuses content that does not match the ref it was filed
under: a tampered store is a *read failure*, not a wrong answer.

| Claim | Proof |
|---|---|
| Content that does not match its ref is refused at read | `test/codebase_get_test.gleam` → `get_refuses_content_that_does_not_match_its_ref_test` |
| A ref that does not match its content is refused at write | `test/codebase_test.gleam` → `hash_mismatch_labels_test` |
| An absent ref is typed absence, not a generic failure | `test/codebase_get_test.gleam` → `get_reports_not_found_for_an_absent_ref_test` |
| A stored definition round-trips through the store | `test/codebase_get_test.gleam` → `get_round_trips_an_inserted_definition_test` |

Run all four:

```sh
gleam test 2>&1 | grep -E "codebase_get_test|hash_mismatch_labels"
```

Identity also holds across the dependency closure: a dependency referenced by
*name* is resolved through the branch namespace to a content ref, and the
module is loaded under the name ref the caller emits. Both directions are
pinned:

| Claim | Proof |
|---|---|
| A name reference resolves through the namespace | `test/run_ref_test.gleam` → `a_name_reference_resolves_through_the_namespace_test` |
| An unbound name reference is missing, not silently stubbed | `test/run_ref_test.gleam` → `a_name_reference_without_a_binding_is_missing_test` |
| A dependency cycle is refused | `run_ref.Cycle` in `src/gleamunison/run_ref.gleam` (`resolve_definition`), reachable only if the store disagrees with its own keys |

---

## 2. Capability proof — what a run may execute

Execution is gated twice: at admission (`publish`) and again at execution
(`run_verified`). The second check exists because a store can be filled by
`sync` or `pkg install` long after admission.

| Claim | Proof |
|---|---|
| Verification is on by default | `test/cli_lifecycle_test.gleam` → `verification_is_on_by_default_test` |
| `GLEAMUNISON_STORE_ALLOW_UNVERIFIED=1` is the explicit hatch (and warns on stderr) | `test/cli_lifecycle_test.gleam` → `the_escape_hatch_accepts_the_usual_spellings_test`; warning text is emitted in `cli_run.execute` |
| Any other value leaves verification on | `test/cli_lifecycle_test.gleam` → `any_other_value_leaves_verification_on_test` |
| The hatch actually runs stored content | `test/run_ref_test.gleam` → `the_escape_hatch_runs_stored_content_test` |
| An absent definition is reported *absent*, not unverified (exit-code ordering) | `test/run_ref_test.gleam` → `absence_is_reported_before_evidence_test` |
| Untrusted execution refuses without an external executor | `test/sandbox_boundary_test.gleam` → `untrusted_requires_external_executor_test` |
| Untrusted execution denies direct host FFI and native jets | `test/sandbox_boundary_test.gleam` → `untrusted_denies_direct_host_ffi_test`, `untrusted_denies_native_jets_test` |

```sh
gleam test 2>&1 | grep -E "cli_lifecycle_test|sandbox_boundary_test|absence_is_reported"
```

---

## 3. Integrity proof — every refusal has an exit code

The exit code is the contract a script reads. Verified against the built
escript (`./build_escript.sh`, then the commands below from any directory):

| Situation | Exit | Stream | Command |
|---|---|---|---|
| Value renders | 0 | stdout: the value only | `./gleamunison_escript run <hash> 40 2` → `42` |
| Function called with no arguments | 1 | stderr: `… is a function of arity 2; pass 2 argument(s), or inspect it without calling` | `./gleamunison_escript run <hash>` |
| Wrong argument count | 1 | stderr: `… expects 2 argument(s), got 1` | `./gleamunison_escript run <hash> 2` |
| Evidence absent and no hatch | 1 | stderr: `… is not verified: evidence: GLEAMUNISON_EVIDENCE_SIGNING_KEY is required…` | `./gleamunison_escript run <hash> 40 2` (no key) |
| Hash absent from the store | 2 | stderr: `not in the store: <hash> (publish it or sync it first)` | `./gleamunison_escript run deadbeef…` |
| Hash malformed | 2 | stderr: `invalid reference: expected 64 hexadecimal SHA-256 digits` | `./gleamunison_escript run nothex` |
| Store override is not absolute | 2 | stderr: `GLEAMUNISON_STORE_DIR must be an absolute path, got: …` | `GLEAMUNISON_STORE_DIR=relative/dir ./gleamunison_escript run <hash>` |
| Usage error | 1 | stderr: usage block | `./gleamunison_escript run` |
| `--json` on a value | 0 | stdout: one JSON line | `./gleamunison_escript run --json <hash> 40 2` |
| `--json` on a function | 0 | stdout: one JSON line, no execution | `./gleamunison_escript run --json <hash>` |

Assert them all at once:

```sh
H=<published-hash>
GLEAMUNISON_EVIDENCE_SIGNING_KEY=x ./gleamunison_escript run $H 40 2 >/dev/null 2>&1; echo "value: $?"        # 0
GLEAMUNISON_EVIDENCE_SIGNING_KEY=x ./gleamunison_escript run $H >/dev/null 2>&1; echo "no-args: $?"           # 1
./gleamunison_escript run deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef >/dev/null 2>&1; echo "absent: $?"  # 2
```

`stdout` carries only the rendered value on the success path, so
`run … | jq` and `run … | wc -l` behave as expected (one line, parseable).

Supporting tests for the gate's own logic:

| Claim | Proof |
|---|---|
| A value cannot be called | `test/run_arity_test.gleam` → `passing_an_argument_to_a_value_is_refused_test` |
| Too few arguments is refused | `test/run_arity_test.gleam` → `too_few_arguments_is_refused_test` |
| Arity follows the curried type chain | `test/run_arity_test.gleam` → `a_curried_type_counts_its_whole_chain_test` |
| Arguments parse as terms, raw text as the explicit fallback | `test/run_arg_parse_test.gleam` → `an_integer_argument_parses_test`, `a_bare_word_is_not_a_term_test` |
| The compiled export contract is `'$eval'/0` only | `test/compile_export_shape_test.gleam` → `a_value_definition_exports_only_eval_0_test`, `a_two_argument_function_exports_only_eval_0_test` |
| JSON output is parseable and capped in depth | `test/cli_output_test.gleam` → `the_envelope_carries_the_ref_and_the_value_test`, `the_depth_cap_truncates_test` |

---

## 4. Freshness — what this does NOT claim

The store is **not time-aware**. It records what was admitted, not when it
stopped being true:

- No expiry. A definition admitted in March executes in October; nothing
  re-tests it between admission and execution.
- No revocation. Evidence is attached to a content hash; the hash does not
  change when the world does, so a verified definition stays verified.
- `sync` and `pkg install` write to the store without re-running the evidence
  gate. `run` re-checks evidence at execution, which is why that second gate
  exists — but it checks the *record*, not the claim's current truth.
- No clock: `inserted_at` appears in the content log (task 9), and nothing
  gates on it.

If a definition must be re-proven, publish a new one. The hash changes with
the content, so a new proof is a new identity; an old hash keeps its old
proof. That is the whole of the freshness story, and nothing in the CLI
claims more.

---

## Reproduce the whole file

```sh
gleam format --check src test
gleam test                                   # 571 passing at this commit
./build_escript.sh
cd /tmp && /path/to/gleamunison_escript run --help   # artifact stands alone
```
