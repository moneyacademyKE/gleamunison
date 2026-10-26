# Glossary

Project terms in their current sense. The linked source or ADR is authoritative
when an older document uses a term differently.

## A

**ADR** — Architecture Decision Record. A dated decision and its context in
`docs/adr/`; not automatically a statement that every proposed step is built.

**Ability / algebraic effect** — A declared operation surface whose `Do` calls
are handled by dynamically scoped process-local handler frames.

**Agent generation** — Bounded composition of prompt storage, schema rendering,
SAP candidate parsing, retry feedback, inferred-type checking, and the ordinary
admitted publication path. It is not a direct model-to-CAS write.

**AST** — Abstract syntax tree. The internal program representation defined in
`src/gleamunison/ast.gleam`; constructor inventory belongs to that source file.

**Authenticated single-node service** — The current verified deployment
classification. It does not include an OS sandbox, native TLS, or a supported
multi-node production topology.

## B

**BEAM** — The Erlang virtual machine targeted by the compiler and runtime.

**Branch** — A mutable pointer to an immutable namespace snapshot. It selects
name bindings; it does not change a definition's content identity.

## C

**CAS** — Content-addressed storage. Immutable bytes are verified against the
hash under which they are stored.

**Codebase** — Definitions, codec/evidence data, namespace snapshots, and branch
pointers managed through the codebase/storage modules. It is not an unconditional
append-only store: explicit retraction and purge have dependency rules.

**Content ref** — A `DefinitionRef` identifying canonical definition content
and inferred type. Distinct from a name ref or branch pointer.

## D

**de Bruijn index** — A positional lexical-variable representation used for
alpha-equivalence and stable identity.

**DefinitionRef** — The content-reference type in `identity.gleam`.

**DETS** — Erlang disk term storage used by durable adapters and journals.

**Dogfood level** — A numbered playbook case exercising runtime behavior.
Executable cases and explicit exclusions are counted separately by the runner.

**Db ability** — The typed application-fact effect: `transact`, exact `get`,
and exact `find` over text-valued EAV facts. Smaller than the full Datalog
engine and backed by its own durable journal.

## E

**Elaboration** — Surface-to-core transformation: name resolution, lexical
binding, ability/type processing, and construction of canonical terms.

**Escript** — An executable Erlang archive. Gleamunison's artifact needs
Erlang/OTP at runtime; it does not bundle the VM.

**Evidence** — An attestation bound to content identity and policy. Evidence
is not a proof of semantic correctness, authorship, authorization, or safety.

**ETS** — Erlang in-memory term storage used by volatile stores and bounded
runtime registries.

## G

**Genesis module** — A checked-in `src/m_*.erl` implementation for a genesis
builtin. Not arbitrary generated scratch and not a filename-based identity
alternative.

## H

**Hindley–Milner inference** — The polymorphic type inference approach used to
compute the type that participates in definition identity.

**Handler frame** — A process-local ability handler on the runtime stack. It is
not an OS isolation boundary or a serializable continuation by itself.

**Hole** — A typed incomplete expression (`?`) that fails loudly if executed.

## L

**LOC policy** — A 250-line cohesion target and an enforced below-500-line
ceiling for touched production files; test files are exempt.

**Loader** — The component that compiles/loads hash-addressed BEAM modules and
tracks their lifecycle.

**LSP** — Language Server Protocol support over stdio; see `docs/LSP.md`.

## M

**MCP** — Model Context Protocol surface for discovery, evaluation, admitted
source publication, and bounded generation through the supervised session.

**Mnesia** — An available storage adapter technology. Its presence is not a
supported production-cluster or application-Db replication claim.

## N

**Name ref** — A reference resolved through the selected branch namespace.
A stored caller's content ref can stay fixed while its name-ref dependency
resolves differently after a branch rebind.

**Namespace** — Immutable name-to-content-ref bindings plus branch/history
machinery. Namespace names are not content identities.

## O

**OTP 27/28/29** — The Erlang/OTP releases in the configured CI matrix. Local
verification on one release does not prove every hosted matrix leg.

## P

**Playbook** — The development/conformance methodology in `docs/PLAYBOOK.md`,
with numbered cases in `docs/playbook/` and explicit exclusion policy.

**Process dictionary** — Per-process Erlang state used for the ability stack
and selected runtime mechanisms. It is not durable application storage.

**Profile** — `local`, `authenticated-remote`, or `untrusted-execution`.
Profiles select explicit admission/startup behavior, not a universal sandbox.

**Prompt ref** — Content identity of a checked generation template. A stored
prompt is an audit artifact, not an admitted application definition.

## R

**REPL** — Interactive read/eval/print loop started with
`./gleamunison_escript repl`.

**Run ref** — The verified stored-execution path shared by CLI and admitted
application routes; route resolution never replaces execution admission.

## S

**SAP** — Schema-aligned parsing of bounded near-miss model output. A parsed
candidate is data for checking, never write authority.

**Scratch overlay** — Session-local definitions that shadow durable names
without modifying branch or CAS state. Publication does not silently absorb
or discard the overlay.

**SHA256** — The cryptographic hash used for canonical content identity and
byte-integrity checks.

**Sync** — Pull-based transfer of missing content over TCP or Erlang
distribution. Sync verifies bytes; execution still applies evidence policy.

## T

**Trace** — A bounded operational HTTP observation, redacted at capture. Not a
durable audit log or distributed-tracing system.

**Turnstile** — The evidence/trust admission policy through which publication
passes. Agent writes do not get a second turnstile or a bypass.

## U

**Untrusted execution** — A refused transport-facing profile in the current
runtime because no approved external OS/container executor is configured.

**`use`** — Lambda-passing surface sugar for sequencing computations; not a
claim of a separate monadic runtime.
