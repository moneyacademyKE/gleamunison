# AGENTS.md

## Commands

- Run the normal verification suite with `gleam test`; passing tests may still print Mnesia/supervisor reports and a `Failed Source` snippet from negative compiler tests.
- Format Gleam sources with `gleam format` before finishing code changes.
- CLI entrypoint is `src/gleamunison.gleam`: `gleam run -- server [port]`, `gleam run -- repl`, `gleam run -- verify scratch.lisp`, `gleam run -- all`, or `gleam run -- levelN`.
- Playbook conformance is not part of `gleam test`; run it explicitly with `bb scripts/run_playbook_tests.clj`.
- `bb.edn` only defines `dogfood-loop`, `dogfood-register`, `dogfood-verify`, and `watch-scratch`; `scripts/README.md` mentions extra task aliases that are not currently defined.
- Build the standalone escript with `./build_escript.sh`; it runs `gleam build`, copies BEAM files, compiles `src/m_*.erl`, and writes `./gleamunison_escript`.

## Architecture Notes

- Core Gleam modules live under `src/gleamunison/`; Erlang FFI implementations live beside them as `src/gleamunison_*.erl`.
- The compile/load path is `parser -> elaborate -> typecheck/inference -> compile -> loader`; `src/gleamunison/pipeline.gleam` wires the focused phases used by REPL and dogfood tests.
- Content-addressed runtime modules are named `m_<hash-suffix>`; checked-in `src/m_*.erl` files are genesis modules, not random scratch files.
- Storage has multiple adapters behind `src/gleamunison/storage.gleam` and `src/gleamunison_storage.erl`: ETS, DETS, partitioned DETS, and Mnesia.
- Sync is split between typed Gleam protocol code in `src/gleamunison/sync*.gleam` and TCP/distributed Erlang FFI in `src/gleamunison_tcp_sync.erl` plus `src/gleamunison_ffi_io.erl`.

## Workflow Gotchas

- The parent directory is not the Git repo; run Git commands from `gleamunison_repo`.
- `manifest.toml` is Gleam-managed; do not edit it by hand.
- `erl_crash.dump`, `.DS_Store`, built BEAMs, and `gleamunison_escript` are artifacts; do not treat them as source unless the task is explicitly about build output.
- Docs contain some stale counts and roadmap prose; prefer `gleam.toml`, `bb.edn`, scripts, and source files when they conflict.
