# Dogfood Loop — Infinite Playbook-Driven Development

## Overview

An autonomous agent loop that continuously extends the gleamunison runtime
through dogfooding. Each iteration produces and validates 50 new integration
levels, updates documentation, and hands off to the next iteration.

## Loop Structure

```
┌─────────────────────────────────────────────────────────┐
│  1. TRIGGER: Previous batch complete (all levels pass)  │
│     + skill/docs updated, commit made                    │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│  2. DISCOVER: Analyze remaining coverage gaps            │
│     - Read explore agent findings                        │
│     - Identify 3-5 high-impact untested areas            │
│     - Design 50 levels per gap priority                  │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│  3. GENERATE: Create batch artifacts                     │
│     - docs/playbook/PLAYBOOK_DOGFOOD_XXXX-XXYY.md       │
│     - src/dogfood_v{N}.gleam (50 level functions)        │
│     - Register in src/dogfood_meta.gleam                 │
│     - Bump ranges in dogfood.gleam + gleamunison.gleam   │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│  4. VERIFY: Build + run all 50 levels                    │
│     - gleam build (catch compile errors)                 │
│     - gleam run -- levelXXXX (all 50 in sequence)        │
│     - gleam test (53 unit tests)                         │
│     - 0 failures required to proceed                     │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│  5. UPDATE: Synthsize learnings into docs                │
│     - Update .commandcode/skills/gleamunison.md           │
│     - Update docs/PLAYBOOK.md badge                       │
│     - Update docs/ARCHITECTURE.md badge                   │
│     - Add findings to key learnings section              │
│     - git commit (with Co-authored-by trailer)            │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│  6. HANDOFF: Signal completion, loop back to step 1      │
│     - Print summary: batch, levels, verifications        │
│     - Output next batch command for bootstrap            │
│     - Invoke `scripts/next_batch.sh`                     │
└─────────────────────────────────────────────────────────┘
```

## State Tracking

The loop tracks its state through the filesystem:

| Artifact | What it stores | How to read |
|---|---|---|
| `src/dogfood_v24.gleam` | Latest batch implementation | `ls src/dogfood_v*.gleam \| tail -1` |
| `docs/playbook/PLAYBOOK_DOGFOOD_2321-2370.md` | Latest playbook | `ls docs/playbook/ \| tail -1` |
| `src/dogfood_meta.gleam` | Level registration map | `grep level[0-9] \| tail -1` |
| `src/dogfood.gleam` | Dispatcher range | `grep "range(1,"` |

### Computing Next Batch

```sh
# Find the latest batch file
latest=$(ls src/dogfood_v*.gleam | sort -t_ -k2 -n | tail -1)
# Extract batch number (24 from dogfood_v24.gleam)
batch=$(echo "$latest" | sed 's/.*v\([0-9]*\)\.gleam/\1/')
next_batch=$((batch + 1))
# Compute level range
start=$((2270 + (batch - 22) * 50 + 1))
end=$((start + 49))
```

## Trigger Conditions

The loop triggers when ALL of the following are true:
- Previous batch's 50 levels all output `Level N: OK`
- `gleam test` reports `53 passed, no failures`
- `.commandcode/skills/gleamunison.md` has been updated with new batch info
- `docs/ARCHITECTURE.md` badge has been updated
- `docs/PLAYBOOK.md` badge has been updated
- A git commit has been made with `Co-authored-by: CommandCodeBot`

## Guardrails

1. **Compile errors are blocking**: If `gleam build` fails, fix before running levels
2. **Any level failure is blocking**: If a level reports anything except `Level N: OK`, fix before proceeding
3. **Unit test regression is blocking**: All 53 unit tests must pass
4. **Batch size must be 50 levels**: No fewer, no more. Keeps iterations predictable
5. **Never skip verification**: Every level in the batch must execute and report OK
6. **Generation must precede verification**: All 50 levels must be written before any are run

## Stopping Conditions

The loop stops (NOT infinite but designed for it) when any guardrail is hit
and cannot be resolved. Otherwise it continues indefinitely with capacity
for ~5000 more levels before stubs run out (stub generation uses modulo
pattern on level numbers, which works for any N).

## Handoff Protocol

When a batch completes, the handoff produces:

```sh
# Print handoff command
echo "=== HANDOFF ==="
echo "Batch $batch complete. Next: batch $((batch + 1)), levels $start-$end"
echo "scripts/next_batch.sh to bootstrap"
```

The next agent invocation receives:
- The previous batch's playbook file (for format reference)
- The latest `src/dogfood_v{N}.gleam` (for implementation style reference)
- The current coverage gap analysis from the skill file's "Key Findings" section
- The next batch number and level range

## Implementation Files

The loop uses these files:

### `scripts/next_batch.sh`
Shell script that computes the next batch number and level range,
creates skeleton playbook and implementation files, bumps ranges,
and prints the handoff context. Run at the START of each iteration.

### `.commandcode/skills/gleamunison.md`
The canonical state file. The agent reads this to understand current
coverage, gaps, and patterns. The agent writes updated counts and
findings back to this file at the end of each iteration.

### `docs/playbook/PLAYBOOK_DOGFOOD_XXXX-YYZZ.md`
Each batch gets its own playbook file describing the 50 levels,
their theme, and success criteria.
