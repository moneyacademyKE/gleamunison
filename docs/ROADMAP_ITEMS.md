# Dogfood Loop — Improvements Roadmap (Status: Dec 2026)

## ✅ Completed (v2 generator + v2 loop)

### 1.1 Fix generator template gap
`(take 49 templates)` → `(take 50 templates)` via `pick-templates` which distributes N levels evenly across all 24 templates. No template is ever dropped.

### 1.2 Reduce build warnings
Generator v2 uses per-template import sets. Each template returns `{:code ... :imports #{...}}`. The writer unions all imports and emits only what's needed. New generated files: ~1 warning (down from ~13). Remaining 1224 warnings are all from pre-existing v2-v83 files.

### 1.3 Add error notification to loop
`loop_infinite.clj` v2: if a batch fails 3 times, writes `batch_N_failure.log` and exits with code 1.

### 2.1 Zombie process management
`loop_infinite.clj` v2 runs `pkill -f "cmd -p"` before spawning each new cmd, preventing zombie accumulation.

### 2.2 Prompt improvement
Shortened from 6 commands to 3: generate (with `--count 50`), register, build+verify+test, update docs. No analysis/exploration trigger words.

### 2.3 Session state management
Loop tracks `last-batch` and `same-batch-count`. If the same batch number is attempted 3+ times (cmd keeps failing), loop exits with error and writes a failure log.

### 3.1 Generate batch coverage diversity
3 new template types: `gen-bool-compile` (Bool literal through pipeline), `gen-type-pretty` (exercise pretty_print), `gen-infer-term` (exercise infer_term). Total: 24 templates.

### 3.2 Reduce generated file size
Per-level imports cut ~10 import lines per file. New files: ~6 imports (from needed modules) vs ~16 (blanket). Also reduces compilation overhead.

### 3.3 Generate real tests (deferred)
Gleam assertion syntax (`let assert` + `panic`) doesn't produce clean error messages. Deferred — would need `gleeunit` integration or custom assertion helpers.

### 4.1 Remove orphaned scripts
Removed: `check_next.clj`, `next_batch.sh`, `auto_dogfood.clj`. All functionality subsumed by `loop_infinite.clj` + `generate_levels.clj` + `dogfood_loop.clj`.

### 4.2 Fix bb.edn task aliases
Restored with plain string syntax: `:dogfood-loop`, `:dogfood-register`, `:dogfood-verify`.

### 4.3 Generator parameterization
Added `--count N` flag. Default 50. Accepts any positive integer.

## ✅ Completed (v2 generator + v2 loop + infrastructure)

### 5.1 Consolidate old generated files
All auto-generated files (v10, v23-v85) regenerated with v2 generator. Per-level imports reduced warnings per file from ~13 to ~8. Total warnings: 1061 (down from 1244). Zero compile errors.

### 5.3 Assertion patterns (partial)
Created `src/dogfood_assert.gleam` with `assert_eq`, `assert_prefix`, `assert_all_ok` helpers. Removed due to Gleam `panic` syntax incompatibilities with string concatenation. Template integration deferred — needs Gleam-native assertion approach.

### 5.4 Generator suite mode
Added `--suite N` flag to `generate_levels.clj`. Generates N batches sequentially, auto-registers each, runs `gleam build` + `gleam run level70` at completion. Numeric sort for batch detection (fixed string-sort bug).

### 5.1 Consolidate old generated files
58 pre-v25 files with 10-56 warnings each. Could regenerate them with the v2 generator to eliminate 1200+ warnings.

### 5.2 Speed up verification
`gleam run level70` runs 82 cert levels sequentially (~2 min). Could parallelize or run `gleam build` only (cert levels run inside build).

### 5.3 Assertion patterns
Custom Gleam assertion helper that prints clean pass/fail messages without `panic`.

### 5.4 Generator suite mode
`--suite` flag that generates and verifies multiple batches in one command.
