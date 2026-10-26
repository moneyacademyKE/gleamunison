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

5. **The BEAM is not just a target — it's a constraint.** Hash-named code
   loading, process-local state, OTP supervisors, and compiler differences across
   the supported OTP 27–29 matrix shape the design. Process isolation is useful
   fault containment, not an operating-system sandbox.

6. **Alternative targets need their own proof.** Non-BEAM environments such as
   WASM isolates may forbid dynamic compilation/loading and require a different
   execution design. Existing analyses are design records, not a claim that a
   Cloudflare/WASM target is currently shipped.

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

- `pub opaque type` where an invariant needs protection; plain value types elsewhere
- Functions return `Result(Ok, Error)` for fallible operations
- Preserve structured domain errors; host FFI boundaries may use strings without
  turning that into a rule that every domain error must be a bare string
- FFI functions use `@external(erlang, ...)` with named parameters
- Erlang FFI modules are files named `gleamunison_*.erl` in `src/`
- Keep compiler/load compatibility checks explicit across supported OTP releases

### Pipeline

```
Text (S-Expr) → Surface AST → Elaboration + inference → Canonical term + type
              → Hash (SHA256) → Codebase (DETS / in-memory)
              → Compile (Erlang source → BEAM binary)
              → Load (code:load_binary into VM)
              → Call $eval()
```

### Building standalone binary

```sh
./build_escript.sh             # Produces ./gleamunison_escript
./gleamunison_escript          # Run with Erlang/OTP; no Gleam needed
./gleamunison_escript repl     # Start interactive REPL
./gleamunison_escript server   # Start HTTP dashboard
```

### Decision records

Significant design decisions are recorded in `docs/adr/`. Read the relevant
ADRs before a change and add a new ADR when a durable decision changes. Do not
rewrite dated decisions or evidence to make history look current; current
implementation status belongs in the guides and verification witnesses.

### Agent read model and scratch overlays

- Agent startup reads the selected branch namespace plus its CAS through
  [ADR 0068](adr/0068-durable-agent-read-model.md). `GLEAMUNISON_BRANCH` selects
  the branch (default `main`); MCP, `/browse`, and `find` expose stored content
  refs, name refs, origin, and branch as separate fields.
- Stored entries retain their AST and identity. Never hash a surface `SRef`
  projection or pretend it is source. Stored graph edges come from the AST.
- MCP `--load` and HTTP `/define` definitions are explicit scratch overlays that
  shadow branch names only for that session. Do not implicitly write scratch
  into CAS.
- The supervised web session owns scratch; MCP reads its current snapshots.
  Never give MCP a second bootstrap-only session or an independent write path.

### Admitted agent writes

- Use [ADR 0070](adr/0070-admitted-agent-writes.md). `agent_publish` accepts
  source, never storage keys, branch names, or store paths. `agent_generate`
  (ADR 0072) adds bounded model candidates to the **same** admitted publication
  path. Neither tool creates a second storage authority. The branch is
  server-selected; receipts carry real content refs that `run` executes.
- Agent publication runs the same pipeline as the CLI: elaboration, tests
  with signed evidence, turnstile, CAS, branch binding. Do not add a second
  admission path or a hash-addressed write tool; that re-opens the
  name-hash/content-hash confusion and skips the turnstile.
- `untrusted-execution` refuses writes before storage opens. Capability
  denial is not an OS sandbox claim (ADR 0067 still owns that boundary).
- A successful write refreshes the supervised snapshot from durable state
  and re-applies only the previous scratch overlay. Fresh durable entries
  win for stored names; scratch shadows by name but stale stored types must
  never survive a refresh. Publication never erases scratch and never
  absorbs it into CAS.

### Bounded agent generation

- Use [ADR 0072](adr/0072-bounded-agent-generation.md). `agent_generate` accepts
  a template, string variables, a small documented signature vocabulary, and
  1–8 attempts. It never accepts a store, branch, credential, provider, or
  arbitrary content key.
- The complete prompt is content-addressed with checked CAS storage. SAP may
  repair a near-miss `{source, signature}` envelope, but admission checks the
  target's inferred type before tests, evidence, or branch writes.
- Every candidate uses `agent_publish`: one target term plus its tests, then
  elaboration, signed evidence, turnstile, CAS, and selected-branch binding.
  Provider errors and rejected candidates become bounded retry feedback;
  exhaustion returns the last error without changing branch bindings.
- Production uses the existing server-owned LLM effect. Deterministic provider
  injection and a loopback completion fixture prove repository behavior; they
  do not claim an external-provider call.
- Patch analysis reports direct stored dependents of newly published names.
  Existing runtime dependencies are name refs: rebinding changes their next
  execution, not their content identity. Do not reconstruct stored source or
  claim automatic dependent regeneration.

### Admitted application routes

- Use [ADR 0071](adr/0071-admitted-app-routes.md). `POST /app/<name>` and
  `POST /app/ref/<content-ref>` execute only definitions bound on the
  server-selected branch. The request cannot select a branch or store, and
  scratch or unbound CAS content returns 404.
- Requests are exactly `{"args":[...]}` with at most eight arguments and
  65,536 bytes. Responses carry the real `ref`, selected `branch`, and JSON
  `value` from the shared `run --json` renderer. Empty input means no args.
- Route resolution is not execution admission. `run_ref` still owns evidence,
  closure loading, and evaluation with unverified execution disabled. `/app/*`
  uses the existing data-write and execution-profile gates before storage.
- Preserve the failure distinction: 400 invalid request/arguments, 413 input
  too large, 404 absent route/content, 403 evidence/profile refusal, and 422
  evaluation failure. Do not flatten these into a generic success envelope.
- Application Db facts use ADR 0069 and remain outside CAS. The route proof
  must restart the Db owner between an HTTP write and read; a warm process
  cache is not durability evidence.

### Deployment and synchronization

Remote actions are not part of local conformance verification. Do not push,
tag, publish, merge, or deploy as a side effect of making tests pass; those are
separate, explicitly approved operations. Sync tests use the configured local
fixtures and verify content/refusal behavior without treating a dry run as
production evidence.

### Production profiles and release claims

- Use the `local`, `authenticated-remote`, and `untrusted-execution` contracts in
  [ADR 0067](adr/0067-production-boundaries.md). They are independent boundaries,
  not one universal production switch. Implementation status and required probes
  live in the [verification matrix](operations/verification-matrix.md).
- Never call an evaluation process scope an OS sandbox. An untrusted profile
  requires an approved external executor and enforceable limits; absence refuses.
- Separate content refs, mutable pointers, signer identity, deployment identity,
  and request authorization. A hash or signature cannot substitute for the others.
- A contract document is not an implemented capability. Record actual refusal and
  success receipts before claiming a profile; never hide manual or skipped gates.
- Boundary work does not authorize a tag, Hex publish, merge, or deployment.

### Content admission and persistence

- Keep definition identity separate from storage encoding: use the versioned
  `definition_codec` payload, then re-hash the decoded AST. Never persist an
  inspect string as a remotely verifiable definition.
- Use `storage.insert_content` / `codebase.insert_raw_checked` at immutable
  boundaries. Raw adapter writes are trusted key/value operations, including
  mutable branch pointers; they are not an untrusted CAS API.
- Use `storage.check_content` for non-destructive corruption detection at a
  known immutable ref. Never classify a failed lookup as a missing ref.
- Definition wire payloads omit spans; identity includes effect requirements
  and unique-type schemas. Old inspect payloads and old effectful/unique refs
  require a backed-up, source-based rebuild. See [ADR 0065](adr/0065-verified-cas-admission.md).
- DETS write and close errors must propagate. A validated batch is not a
  multi-record crash transaction, and validation is not an execution sandbox.

### Durable application data

- Use [ADR 0069](adr/0069-durable-db-ability.md). `Db.transact`, `Db.get`, and
  `Db.find` are the only V1 application-fact surface; facts use the EAV pair
  shape with text values, and transactions are atomic DETS journal records.
- Application facts live in `application.dets` beside the configured code
  store, not in definition CAS. The supervised owner replays committed records
  after restart; it does not invent durable state from a process dictionary.
- `Db` calls are effectful and type-checked at the ability boundary. Capability
  denial must happen before a storage handler runs. This is not an OS sandbox;
  untrusted execution still follows the external-executor refusal contract.
- V1 exact reads are deliberate. Do not claim arbitrary Datalog joins,
  temporal queries, or multi-node database behavior without new proofs.

### Interactive REPL

Start the interactive loop to dogfood the codebase:
```sh
./gleamunison_escript repl
```
The REPL bootstraps `"Console"`, `"add"`, and `"read_line"`, and supports:
- `(define name expr)` to define names
- expressions (like `(add 1 2)`) to evaluate them
- `(do Console print "hello")` to trigger algebraic effects.

### LOC constraints and conformance

Keep modules cohesive: target 250 LOC, and keep touched production files below
the enforced 500-LOC ceiling. Test files are exempt. Split along ownership and
composition boundaries, not into arbitrary tiny-file confetti.

The playbook runner parses every numbered level and distinguishes executable
passes, failures, skips/timeouts, and explicit SHA-pinned exclusions. Exclusions
are not passes. Run `bb scripts/run_playbook_tests.clj`; use `--strict` only as
a completeness report, because it intentionally rejects every exclusion.

Current test counts, playbook totals, artifact measurements, and environment
exclusions belong in the latest dated verification witness, not in a permanent
scoreboard here. The self-hosted Datalog engine and durable application `Db`
are related in vocabulary but have separate execution and persistence contracts.



