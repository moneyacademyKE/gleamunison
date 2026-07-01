# Dogfood Loop — Improvements Roadmap

## Priority 1 (Immediate Impact)

### 1.1 Fix generator template gap
Template #21 (`gen-loader-limit`) is never consumed because `(take 49 templates)` drops the 21st pattern after 2 full cycles. Fix: distribute 50 across 21 templates evenly — 8 patterns get 2x, 13 patterns get 3x = 50.

### 1.2 Reduce build warnings
1224 warnings across all generated v*.gleam files. The generator imports a standard set of 15+ modules but each batch only uses a subset. Fix: make generator emit per-level imports instead of file-level blanket imports, or use `import gleam/*.{}` syntax to silence.

### 1.3 Add error notification to loop
If a batch fails (build error, test failure, timeout), the loop currently logs and continues. Should exit non-zero or write a failure log.

## Priority 2 (Stability)

### 2.1 Zombie process management
`loop_infinite.clj` should kill any existing `cmd` processes before spawning new ones. Currently each spawned cmd accumulates until manual cleanup.

### 2.2 Prompt improvement
The AI prompt for each batch needs to be even more concise to avoid exploration deadlocks. Current prompt is 6 imperative commands — could be shortened to 3.

### 2.3 Session state management
If the AI gets stuck on a batch, the loop retries indefinitely (same batch, same prompt). Should detect retries and escalate (different prompt, skip batch, etc).

## Priority 3 (Quality)

### 3.1 Generate batch coverage diversity
All generated batches (v25-v83) use the same 21 template patterns with varied values. Coverage is broad but shallow. Should introduce new template types for deeper coverage.

### 3.2 Reduce generated file size
Each v*.gleam is ~25KB. With 60+ generated files, that's ~1.5MB of highly repetitive code. Could consolidate into fewer files or use a data-driven approach.

### 3.3 Generate real tests
The generated levels test that things compile and don't crash. No generated levels verify correctness of results. Could add assertion patterns to templates.

## Priority 4 (Infrastructure)

### 4.1 Rename/remove unused scripts
- `next_batch.sh` — deleted, reference removed from prompts
- `auto_dogfood.clj` — deleted, replaced by `loop_infinite.clj`
- `check_next.clj` — orphaned, no callers

### 4.2 bb.edn task aliases
The `:task` map syntax doesn't work in Babashka 1.12. Tasks defined as maps with `{:task "..."}` silently fail. Either fix or remove.

### 4.3 Generator parameterization
`generate_levels.clj --batch N --start S` currently hardcodes 49 levels + 1 cert. Could accept `--count` and `--templates` for variable batch sizes.
