# AGENTS.md

## Commands

Run commands from this repository root.

- `gleam test` — unit and integration suite. Negative compiler tests may print
  expected `Failed Source` snippets; Mnesia/supervisor reports are not by
  themselves a failure verdict.
- `gleam format --check src test` — formatting gate; use
  `gleam format src test` to format changes.
- `gleam check --target erlang` — Erlang-target type check.
- `gleam run -- server [port]`, `repl`, `verify <file.lisp>`, `all`, or
  `level<N>` — direct CLI entry points (`N` is an integer).
- `bb scripts/run_playbook_tests.clj` — playbook conformance; this is separate
  from `gleam test` and keeps explicit exclusions distinct from passes.
- `bb scripts/verify_production_boundaries.clj` — integrated gate and dated
  witness. Review its generated witness/escript changes separately.
- `./build_escript.sh` — build `./gleamunison_escript`; the artifact still
  requires Erlang/OTP at runtime.

See `scripts/README.md` for the individual verification batteries and
`docs/README.md` for current documentation versus historical evidence.

## Architecture

- Gleam modules live under `src/gleamunison/`; Erlang FFI and supervisor code
  live beside them as `src/gleamunison_*.erl`.
- The main path is `parser -> elaborate -> typecheck/inference -> compile ->
  loader`; `src/gleamunison/pipeline.gleam` wires the focused phases.
- Definition identity includes canonical term and inferred type. Content refs,
  name refs, and mutable branch pointers are different values.
- Content-addressed runtime modules are named `m_<hash-suffix>`. Checked-in
  `src/m_*.erl` files are genesis modules, not generated scratch.
- Storage adapters live behind `src/gleamunison/storage.gleam` and
  `src/gleamunison_storage.erl`: ETS, DETS, partitioned DETS, and Mnesia.
- MCP and HTTP share the supervised durable/scratch read model. Agent writes
  and bounded generation must use the existing publication/evidence path.
- Application `Db` facts use their own journal; they are not definition CAS.
- `/app` routes execute selected-branch admitted content only.
- Read `docs/ARCHITECTURE.md` and the relevant ADR before changing identity,
  admission, storage, application state, service authority, or sync.

## Working agreements

- Keep production modules cohesive: target 250 LOC, stay below the enforced
  500-LOC ceiling for touched files. Test files are exempt.
- Add a regression before a fix and prove refusal paths for boundary changes.
- Keep documentation claims aligned with source and scripts. Put volatile
  counts and measurements in dated witnesses, not throughout current guides.
- `manifest.toml` is Gleam-managed; do not edit it by hand.
- `erl_crash.dump`, `.DS_Store`, built BEAMs, and `gleamunison_escript` are
  artifacts, not source. Do not treat generated witnesses as hand-authored
  guides.
- Do not rewrite dated audits, ADRs, or verification history to describe the
  present; add a current document or a new decision instead.
