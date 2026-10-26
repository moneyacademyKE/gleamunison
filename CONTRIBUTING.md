# Contributing to gleamunison

## Development environment

Use the toolchain exercised by CI:

- Erlang/OTP 27, 28, or 29
- Gleam 1.19.1 and rebar3 3
- Babashka for the conformance and verification scripts
- Git
- Bun only when running the dashboard-safety battery on its own

```sh
git clone https://github.com/moneyacademyKE/gleamunison.git
cd gleamunison
gleam deps download
gleam test
```

The OTP/OS matrix is defined in `.github/workflows/test.yml`. A local run on
one OTP release is not proof that every hosted matrix leg passed.

## Verification

Run the narrowest useful test first, then the relevant gates:

```sh
gleam test
gleam format --check src test
gleam check --target erlang
bb scripts/run_playbook_tests.clj
bb scripts/verify_production_boundaries.clj
```

`gleam test` is not the playbook conformance runner. Use
`bb scripts/run_playbook_tests.clj` for the default playbook gate; explicit
exclusions are not passing coverage. `gleam run -- level42` runs one playbook
level directly, while `gleam run -- all` runs the levels available through the
CLI.

The integrated boundary gate builds the artifact and writes a dated witness
under `docs/verification/`. Review that generated change separately from source
changes. See `scripts/README.md` for individual batteries and
`docs/operations/verification-matrix.md` for what each gate proves.

Add a regression test before fixing a defect. For boundary work, prove the
refusal as well as the success path: wrong branch, wrong profile, malformed
input, exhausted budget, and restart behavior where relevant.

## Project layout

The execution pipeline is:

```text
Text (S-Expr) → surface AST → elaboration/type inference → canonical term + type
              → SHA256 content ref → codebase → BEAM compile/load → $eval
```

- `src/gleamunison/` — Gleam compiler, runtime, storage, services, and CLI modules
- `src/*.gleam` — top-level executable and dogfood entry points
- `src/gleamunison_*.erl` — Erlang FFI, supervisors, storage, and service boundaries
- `src/m_*.erl` — checked-in content-addressed genesis modules
- `test/` — unit, integration, and snapshot tests
- `gleamunison_datalog/` — self-hosted Datalog engine
- `docs/adr/` — architecture decision history
- `docs/playbook/` — executable and explicitly excluded conformance levels
- `scripts/` — Babashka/shell verification and operational tooling

Start with `docs/README.md` and `docs/ARCHITECTURE.md`; the source tree, not a
hand-maintained module count, is the inventory.

## Code conventions

- Keep modules cohesive and intention-revealing. Aim for at most 250 LOC;
  production files touched by a change must stay below the enforced 500-LOC
  ceiling. Test files are exempt.
- Use opaque types where they protect an invariant, not as decoration.
- Preserve typed errors at module boundaries; do not flatten useful causes into
  log strings.
- Erlang FFI modules use `gleamunison_*.erl`; external functions use explicit
  `@external(erlang, ...)` declarations.
- Content-addressed runtime modules use `m_<last_8_hex_chars>`.
- Keep content identity, branch names, evidence, application state, provider
  configuration, and deployment authority separate.
- Format Gleam changes with `gleam format src test` before the format check.

## Design and documentation

For significant changes, read the relevant ADRs and name the trade-off before
implementation. Record a new accepted decision in `docs/adr/` when architecture,
storage, API authority, runtime boundaries, or operational policy changes. Do
not rewrite a dated ADR or verification witness to make history look current.

Update the current guide affected by the change. Keep volatile test counts and
artifact measurements in dated witnesses rather than copying them across the
documentation set.

## Build the standalone artifact

```sh
./build_escript.sh
./gleamunison_escript repl
./gleamunison_escript server 8080
```

The escript needs Erlang/OTP at runtime. `docs/BUILD_ESCRIPT.md` covers the
artifact and reproducibility contract.

## Pull requests

1. Create a focused branch and keep commits atomic.
2. Run the relevant tests and verification gates; report actual results and
   exclusions rather than claiming an unrun matrix.
3. Add or update ADRs and current documentation when the contract changes.
4. Update `CHANGELOG.md` for user-visible changes.
5. Open a PR with the rationale, verification evidence, and linked issue.

For development conventions and conformance policy, see `docs/PLAYBOOK.md`.
