# Gleamunison Project Playbook

## How to work on this project

### Principles

1. **Spec-first, implement second.** Every module starts as type definitions,
   function signatures, and design rationale. Implementation fills in `todo`
   values only after the spec is stable.

2. **De-complection.** The central design discipline (Rich Hickey). If two
   concerns can be separated, they must be separated. Every type and function
   signature is a binding contract — if it mixes concerns, it's wrong.

3. **Content-addressing is the core constraint.** Identity = hash of serialized
   form. If it shouldn't change the hash, it doesn't go in the form. Types (inferred)
   DO go in the hash because they determine runtime behavior (ADR-0009).

4. **Genesis builtins, not primitives.** There is no "builtin" identity system.
   Everything that exists has a hash. Primitives are seeded into every codebase
   via a genesis block with pre-computed hashes.

5. **The BEAM is not just a target — it's a constraint.** Hot code swapping,
   process isolation, process dictionary, `code:load_binary/3`,
   `compile:file/2` with OTP 29's `{ok, Mod, []}` return format, distribution
   via EPMD — these are part of the design, not implementation details.

6. **Sandboxed Target Constraints (Cloudflare/WASM).** For non-BEAM sandboxed environments (such as Cloudflare Workers or WebAssembly isolates), dynamic code compilation and loading are blocked by the security sandbox. Code execution in these environments must use static-worker AST interpreters rather than dynamic compilers.

### Workflow

1. **Design:** Types and signatures go in `src/` as Gleam code.
2. **Implementation:** Fill in functions one at a time.
3. **Testing:** `gleam test` runs the unit test suite.
4. **Change process:** Every architectural change follows the Hickey loop:
   a. Identify the gap
   b. Analyze what's complected
   c. Propose the fix
   d. Update all affected types and signatures
   e. Update documentation (ADRs, README, ARCHITECTURE)

### Code conventions

- `pub opaque type` for anything that must maintain invariants (Hash, Codebase, Loader)
- `pub type` for value types (Term, Definition, Type)
- Functions return `Result(Ok, Error)` for fallible operations
- All error types are defined as custom types, never bare strings
- FFI functions use `@external(erlang, ...)` with named parameters
- Erlang FFI modules are files named `gleamunison_*.erl` in `src/`
- OTP 29 quirks: `compile:file/2` returns `{ok, Mod, []}`, use catch-all guards

### Pipeline

```
Text (S-Expr) → AST (Gleam types) → Hash (SHA256) → Codebase (DETS / in-memory)
                                                    → Compile (Erlang source → BEAM binary)
                                                    → Load (code:load_binary into VM)
                                                    → Call $eval()
```

### Building standalone binary

```sh
./build_escript.sh    # Produces ./gleamunison (281KB escript)
./gleamunison         # Run without Gleam, just Erlang/OTP
```

### Decision records

Every significant design decision is recorded as an ADR in `docs/adr/`.
Before making a change, read the relevant ADRs. After making a change,
write a new ADR or update an existing one.

### Deployment and Synchronization

Always pre-verify all remote transfers:
1. Execute a dry run (`env -u GITHUB_TOKEN git push --dry-run`).
2. Run standard pushes (`env -u GITHUB_TOKEN git push`).
3. Never use standard `--force`. If history rewriting is required, use `--force-with-lease --force-if-includes`.

### Interactive REPL

Start the interactive loop to dogfood the codebase:
```sh
./gleamunison
```
The REPL bootstraps `"Console"`, `"add"`, and `"read_line"`, and supports:
- `(define name expr)` to define names
- expressions (like `(add 1 2)`) to evaluate them
- `(do Console print "hello")` to trigger algebraic effects.



### LOC Constraints
All Gleam/Erlang source files MUST be strictly under 250 LOC. If any module grows close to this limit, decompose it into high-cohesion, low-coupling sub-modules. Keep type definitions separated from logic files where necessary to avoid circular dependency imports.

Current conformance: 1170 real dogfood levels + 53 unit tests = 1223 total conformance verifications across 22 playbook files (batches 1-21). No failures. v3.3.0 adds batches 20-21 with 200 levels covering type pretty edges, lexer/parser edges, elaborate all surface forms, compile pattern depth, REPL error codes, count_brackets edges, sync push validation, validate_handler edge cases, stress testing (500 compiles, 10k inserts), compile→load→eval roundtrip, template+config+filepath edges, and 16 cross-module chains.

