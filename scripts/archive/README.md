# Archived scripts

Scripts whose job is finished. They are kept because the history is useful, not
because they still work — none of them is part of the build, the gate battery,
or any `bb` task.

| Script | What it did | Why it is here |
|---|---|---|
| `make_placeholders.clj` | scanned the playbook for levels with no `gleam` code block and wrote stub `todo` bodies into the markdown | the playbook no longer has generated stubs to write; levels without executable cases are now reported as exclusions by the runner, which is the honest signal |
| `add_level_placeholders.clj` | generated `levelXXX()` stubs in `src/dogfood.gleam` for new levels | levels are dispatched from the current module layout; stub generation would resurrect the placeholder era |
| `refactor_playbooks.clj` | bulk structural rewrites across the playbook markdown files | one-off migration of the playbook format, already applied |
| `refactor_dispatch.clj` | regenerated `src/gleamunison.gleam` and `src/dogfood.gleam` from an embedded template | the template still emits three commands (`server`, `demo`, `repl`) and calls `repl.start_repl()`, which no longer exists; running it would delete sixteen commands and leave a tree that does not compile |

Running any of them against the current playbook would rewrite level text and
invalidate every fingerprint in `../playbook_exclusions.edn`, which the
default-mode playbook gate treats as a failure. Read them, don't run them.

The live scripts are described in `../README.md`.
