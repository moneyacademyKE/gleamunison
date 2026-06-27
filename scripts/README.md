# Utility Scripts

Clojure/Babashka scripts for gleamunison development automation.

**Requirements:** [Babashka](https://babashka.org/) (`bb`) installed.

## Scripts

### `run_playbook_tests.clj`
**Purpose**: Run the 1000-level dogfood playbook conformance suite with timeout management.

Parses playbook markdown files from `docs/playbook/`, extracts S-expression test cases, spawns `gleam run -- levelN` per level, and reports pass/skip/fail results. Wraps each execution in a Clojure future with 30-second timeout to prevent hanging processes. Inherits stderr stream to avoid pipe buffer deadlocks.

```sh
bb scripts/run_playbook_tests.clj
```

### `make_placeholders.clj`
**Purpose**: Generate placeholder test bodies for dogfood levels that don't have implementations yet.

Scans the playbook files for levels that lack `gleam` code blocks and generates stub `todo` expressions. Operates on a predefined set of target levels. Modifies playbook markdown files in-place with generated stubs.

```sh
bb scripts/make_placeholders.clj
```

### `add_level_placeholders.clj`
**Purpose**: Add placeholder entries to `src/dogfood.gleam` for new playbook levels.

Generates `levelXXX()` function stubs that delegate to `todo` in the main dogfood dispatch module. Ensures new levels are callable from `gleam run` without manual boilerplate.

```sh
bb scripts/add_level_placeholders.clj
```

### `refactor_playbooks.clj`
**Purpose**: Refactor playbook markdown files across structural changes.

Used when the playbook format or level numbering changes. Applies transformations across all 10 playbook files consistently.

```sh
bb scripts/refactor_playbooks.clj
```

### `refactor_dispatch.clj`
**Purpose**: Regenerate dispatch logic in `src/dogfood.gleam`.

When new levels are added, this script regenerates the match/case dispatch in the main dogfood entry point to include all level handlers.

```sh
bb scripts/refactor_dispatch.clj
```

### `test_parser.clj`
**Purpose**: Test the gleamunison S-expression parser against the full 1000-level playbook.

Parses all playbook files, extracts S-expression test cases from `gleam` code blocks, feeds them through the parser, and reports any parse errors or syntax issues.

```sh
bb scripts/test_parser.clj
```

## Common Patterns

All scripts use Babashka's process management (`babashka.process`) for spawning Gleam subprocesses and `babashka.fs` for file system operations. Playbook files follow the format in `docs/playbook/PLAYBOOK_DOGFOOD_XXXX-YYYY.md` — see `docs/PLAYBOOK.md` for the format specification.
