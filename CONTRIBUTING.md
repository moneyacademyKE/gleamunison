# Contributing to gleamunison

## Development Environment

**Requirements:**
- Erlang/OTP 29+
- Gleam 1.0+
- Babashka (for Clojure utility scripts)
- Git

**Setup:**
```sh
git clone https://github.com/moneyacademyKE/gleamunison.git
cd gleamunison
gleam test          # verify everything works
```

## Running Conformance Tests

The dogfood playbook contains 1000 conformance levels:

```sh
# Run all levels via Gleam
gleam run -- all

# Run a specific level range
gleam run -- level42

# Run via Babashka (includes timeout management)
bb scripts/run_playbook_tests.clj
```

## Project Architecture

gleamunison is a content-addressed language runtime on the BEAM. The pipeline:

```
Text (S-Expr) → AST (Gleam types) → Hash (SHA256) → Codebase (DETS/in-memory)
                                                    → Compile (Erlang → BEAM)
                                                    → Load (code:load_binary)
                                                    → Call $eval()
```

**Key directories:**
- `src/gleamunison/` — 27 Gleam core library modules (parser, typechecker, compiler, etc.)
- `src/*.erl` — Erlang FFI: HTTP server, storage (DETS/Mnesia), escript entry point, supervisor
- `src/m_*.erl` — 52 content-addressed genesis modules (hash-addressed builtins)
- `test/` — Unit and snapshot tests (birdie)
- `docs/adr/` — 34 Architecture Decision Records
- `docs/playbook/` — 1000-step dogfood development playbook in 10 volumes
- `scripts/` — Clojure/Babashka utility scripts

## Code Conventions

- **LOC limit**: All Gleam/Erlang source files strictly under 250 lines. Decompose before crossing the limit.
- **Opaque types**: Use `pub opaque type` for types that maintain invariants (Hash, Codebase, Loader)
- **Error types**: All error types are custom types, never bare strings
- **FFI**: External functions use `@external(erlang, ...)` with named parameters
- **Erlang modules**: Named `gleamunison_*.erl` in `src/`
- **Module names**: Content-addressed modules use `m_<last_8_hex_chars>` format

## Development Workflow

1. **Design**: Types and signatures first in Gleam source
2. **Implement**: Fill in functions one at a time
3. **Test**: `gleam test` runs the unit suite; `gleam run -- all` runs dogfood levels
4. **Document**: Every architectural change follows the Hickey loop:
   - Identify the gap
   - Analyze what's complected
   - Propose the fix
   - Update all affected types and signatures
   - Update documentation (ADRs, README, ARCHITECTURE)

## Architecture Decision Records

Every significant design decision is recorded as an ADR in `docs/adr/`.
Before making a change, read the relevant ADRs. After making a change,
write a new ADR or update an existing one. ADRs use the format:

```markdown
# ADR-NNNN: Brief Title

Status: Proposed | Accepted | Superseded | Amended

## Context
...

## Decision
...

## Consequences
...
```

## Build Standalone Binary

```sh
./build_escript.sh    # Produces ./gleamunison_escript
./gleamunison_escript repl   # Start REPL
./gleamunison_escript server # Start web dashboard on :8080
```

## Pull Request Process

1. Create a branch from `main`
2. Ensure `gleam test` passes
3. Ensure `gleam run -- all` passes (or note known skips)
4. Write or update ADRs for design decisions
5. Update CHANGELOG.md if the change is user-visible
6. Open a PR with a clear description of the change and rationale

## Questions?

Open an issue on GitHub or start from `docs/PLAYBOOK.md` for the full development playbook.
