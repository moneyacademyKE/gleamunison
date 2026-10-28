# Five simplicity improvements — 2026-10-28

## Scope

Audit of the current `gleamunison` tree at `b75cbeb`: 129 Gleam modules and 106 Erlang modules, 28,613 lines across production Gleam/Erlang files. The family Bankai queue had no open Gleamunison implementation work, so this audit selected five bounded improvements rather than inventing a new subsystem.

The selection rule is strict: remove a second authority, stop discarding information, or make an existing boundary honest. No new storage engine, query language, cache, registry, or abstraction layer.

## Selected improvements

### 1. One canonical definition-reference rendering

**Evidence:** `identity.gleam` owns hashes and parsing, but ref-to-hex and runtime-module rendering are reimplemented in `namespace_codec.gleam`, `prompt.gleam`, `store_deps.gleam`, `run_error.gleam`, `cli_sync.gleam`, `cli_publish.gleam`, `cli_purge.gleam`, `codebase_index.gleam`, `compile.gleam`, and `effects.gleam`.

**Change:** add canonical `identity.ref_hex` and `identity.runtime_module_name`; delegate existing call sites to them. Preserve every rendered byte and public caller contract.

**Rejected alternative:** another formatting utility module. Identity rendering belongs with identity, not in a new grab-bag.

### 2. One namespace-to-binding snapshot

**Evidence:** `name_snapshot.from_namespace` and `dependency_snapshot.read` contain the same `namespace.names` → `namespace.get` → `repl_eval.ref_for_name` fold, including the same invariant assertion.

**Change:** `dependency_snapshot` reuses `name_snapshot.from_namespace` instead of maintaining a second copy.

**Rejected alternative:** extract a third snapshot abstraction. The existing snapshot is already the right owner.

### 3. Dependency reads cannot pretend failure is empty

**Evidence:** unchecked functions in `store_deps.gleam` use `result.unwrap([])` after snapshot reads. A storage or namespace failure therefore looks exactly like “no dependencies,” “no dependents,” or “no other names.” Current production callers already use checked/snapshot APIs; unchecked callers remain in tests.

**Change:** remove the silent compatibility functions, add checked variants where missing, and migrate tests to explicit `Result` assertions. Retain the existing broken-adapter tests as the failure contract.

**Rejected alternative:** log and return an empty list. Logging does not make a false answer true.

### 4. Evidence reads cannot pretend failure is no evidence

**Evidence:** `evidence.for_subject` converts `snapshot(adapter)` failure into `[]`, although `snapshot` explicitly promises that I/O failure is never an incomplete snapshot. Production admission already uses `Snapshot`; the silent compatibility reader is used by tests.

**Change:** remove `for_subject`, migrate tests to `snapshot` + `from_snapshot`, and add a direct broken-adapter proof that read failure remains visible.

**Rejected alternative:** a second checked compatibility function beside the silent one. That preserves the trap instead of removing it.

### 5. One LLM budget settlement path

**Evidence:** `llm.complete_env` and `llm_middleware.budget_handler` separately implement release, spend, success/failure reporting, and repeated `let assert Ok(Nil)` calls. The two paths can drift, and a budget-backend failure currently crashes after the provider call rather than producing an explicit outcome.

**Change:** introduce a small shared settlement boundary for the existing budget FFI, then use it from both call paths. Preserve admission, metering values, handler results, and exactly-once slot release; make settlement failure explicit instead of asserted.

**Rejected alternative:** more retry/fallback policy. This change only removes duplicated bookkeeping; it does not alter provider behavior.

## Verification

Each improvement lands independently with focused regression coverage where behavior changes, followed by `gleam test`, `gleam format --check src test`, `gleam check --target erlang`, and `git diff --check`. Final verification includes the playbook and production-boundary contract. No push, release, deployment, tag, or merge is part of this work.
