---
name: gleamunison
description: Work with the gleamunison codebase — a content-addressed language runtime on the BEAM, built in Gleam. Use when adding features, fixing bugs, changing admitted agent writes, or verifying the runtime.
---

# Gleamunison

Gleamunison is a content-addressed language runtime on the Erlang BEAM.
Definition identity includes the canonical term and inferred type. Algebraic
effects use process-local handler frames; the host FFI and deployment profile
remain separate trust boundaries.

Read `AGENTS.md`, `docs/ARCHITECTURE.md`, and the relevant ADR before changing
a contract. Source and scripts outrank old counts or historical prose.

## Source map

```text
src/gleamunison/
  ast, lexer, parser                 syntax and core values
  elaborate, elab_*                  surface-to-core elaboration
  inference, infer_*, typecheck      types and checking
  identity, definition_*             content identity and references
  codebase, storage, namespace*      CAS, adapters, names, branches
  compile, loader, pipeline          BEAM emission and loading
  effects, capability, turnstile     effect and admission policy
  run_ref, run_closure, run_error    verified stored execution
  agent_read_model, agent_publish    durable/scratch reads and admitted writes
  generation_*, prompt, sap, patch   bounded generation composition
  db                                 durable application Db contract
  app_path, app_route, app_response  admitted HTTP application routes
  mcp*, http, lsp*                   service surfaces
  cli_*, repl*                       command and interactive surfaces
src/*.gleam                          executable and dogfood entry points
src/gleamunison_*.erl                host FFI, supervisors, service boundaries
src/m_*.erl                          checked-in genesis implementations
test/                                unit, integration, and snapshot tests
gleamunison_datalog/                 self-hosted Datalog engine
docs/adr/                            decision history
docs/playbook/                       conformance levels and exclusions
scripts/                             verification and operational tooling
```

Do not resurrect deleted `dogfood_v*`, `filepath`, `template`, `config`,
`health`, `metrics`, or CAS type-adapter modules from old documentation.
The filesystem is the module inventory.

## Invariants

1. Keep content refs, name refs, branch pointers, and evidence distinct.
2. Never hash a surface projection of a stored term and call it the stored
   definition's identity.
3. Scratch is session-local. Do not copy it into CAS implicitly.
4. Agent source publication and generation use `agent_publish` and the normal
   evidence/turnstile path. Do not add direct CAS/branch write tools.
5. Generation checks inferred type, not the candidate's self-declared type.
   Exhausted attempts must not add branch bindings.
6. Application `Db` facts use their journal; they are not code CAS or a second
   namespace.
7. `/app` executes only selected-branch admitted content. Scratch and arbitrary
   unbound CAS refs are not HTTP targets.
8. In-process effects, budgets, and supervisors are not an OS sandbox.
9. Do not claim TLS, external execution, multi-node production, or hosted CI
   success unless the current implementation and evidence actually prove them.

## Verification

Run from the repository root:

```sh
gleam test
gleam format --check src test
gleam check --target erlang
bb scripts/run_playbook_tests.clj
bb scripts/verify_production_boundaries.clj
```

Use targeted tests while iterating. `gleam test` and the playbook runner are
different suites. Explicit playbook exclusions are not passes. The integrated
gate builds artifacts and writes a dated witness; inspect generated changes
before staging anything.

Useful direct commands:

```sh
gleam run -- repl
gleam run -- server 8080
gleam run -- verify path/to/file.lisp
gleam run -- level42
./build_escript.sh
```

See `scripts/README.md` for individual boundary batteries. Local results on
one OTP/OS pair do not prove the configured CI matrix.

## Change workflow

1. Reproduce the defect or write the smallest failing contract test.
2. Read the owning module and its tests; do not infer architecture from an old
   module list.
3. Make the smallest compositional change. Keep authority in its existing
   owner rather than adding a parallel path.
4. Exercise success and refusal behavior. For durable state, include restart;
   for branches, include wrong/missing branch behavior.
5. Format and run the relevant gates.
6. Update current docs and add an ADR when a durable architectural decision
   changes. Do not rewrite dated evidence to look current.
7. Stage only intentional files; keep generated artifacts and witnesses
   separate unless the task explicitly includes them.

## Code conventions

- Aim for 250 LOC per production module; touched files must remain below the
  enforced 500-LOC ceiling. Test files are exempt.
- Use opaque types when they protect an invariant, not automatically.
- Preserve structured errors through domain boundaries. Host FFI may use
  strings at its edge, but do not erase useful domain causes unnecessarily.
- Erlang FFI modules use `gleamunison_*.erl` and explicit `@external`
  declarations. Gleam strings are UTF-8 binaries on the BEAM.
- Runtime content modules use `m_<last_8_hex_chars>`.
- Format Gleam with `gleam format src test`; do not hand-align generated output.

## Common implementation paths

### Change an AST or type contract

Trace the complete path through parser/elaboration, inference, canonical
identity/codec, compiler, loader, and relevant projections. Add tests for both
identity and execution; a compiler-only change can otherwise produce content
that cannot be published or decoded.

### Change agent reads or writes

Start with `agent_read_model`, `agent_publish`, `session_refresh`,
`mcp_session`, and `mcp_write`. Prove that a returned content ref can execute,
that scratch stays an overlay, and that untrusted execution refuses before
storage opens.

### Change generation

Start with `generation_loop`, `generation_candidate`, `generation_request`,
`mcp_generation`, `prompt`, `sap`, `schema_printer`, and `patch`. Keep provider
configuration server-owned and retries bounded. Use deterministic providers
for tests; external accounts are not required for repository acceptance.

### Change application data or routes

Start with `db`, the `gleamunison_app_db` owner, `app_route`, `run_ref`, and
HTTP session supervision. Prove journal recovery and selected-branch
admission, not merely an in-process return value.

## Playbook changes

Playbook source is under `docs/playbook/`; policy and explicit exclusions live
in `scripts/playbook_policy.clj` and `scripts/playbook_exclusions.edn`. Use
`bb scripts/run_playbook_tests.clj` to evaluate the documented cases through
the real REPL. Do not invent old generated `dogfood_v*` batches or count an
excluded prose-only level as a pass.

Historical analyses remain useful as evidence of past decisions, not as setup
instructions. `docs/README.md` is the navigation entry point.
