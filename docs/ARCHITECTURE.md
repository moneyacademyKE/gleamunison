# Gleamunison architecture

## Scope

Gleamunison is a content-addressed language runtime on the Erlang BEAM,
implemented in Gleam with Erlang FFI at host boundaries. This guide describes
the current runtime. Dated design decisions live in `docs/adr/`; measured
release claims live in `docs/verification/`.

The central rule is separation of concerns: immutable code, mutable names,
application facts, evidence, provider configuration, and deployment authority
are different values with different owners.

## Identity and execution

A definition's identity is SHA256 over its canonical term and inferred type.
Alpha-equivalent terms share an identity; a name or branch does not silently
become part of the content hash. Builtins have declared types, so inference
does not place an unknown-type sentinel in a stored identity.

```text
source text
  → lexer/parser → surface AST
  → elaboration + Hindley–Milner inference → canonical term + type
  → definition codec + SHA256 → content ref
  → verified CAS admission and selected-branch name binding
  → dependency closure → Erlang source/BEAM → code:load_binary
  → $eval, optionally applying run arguments
```

`identity`, `definition_codec`, `definition_refs`, and `run_closure` own the
identity/dependency vocabulary. `compile` and `loader` emit and load hash-named
modules such as `m_e8e52932`. Genesis `m_*.erl` modules are checked-in native
implementations, not arbitrary scratch output.

The supplied definition is the only execution authority. Compilation never
replaces a stored AST or reference with a registry-selected host body, and a
missing definition has no fallback beyond declared bootstrap types and
available genesis builtins. The former jet registry and its policy switch were
removed by [ADR 0074](adr/0074-stored-definition-execution-authority.md);
native FFI remains at the explicit genesis boundary.

Running by content ref does not fetch from a peer implicitly. The selected
branch resolves named dependencies; missing or unreadable content is an error,
not an empty program.

## Codebase, storage, and branches

`storage.StorageAdapter` provides the primitive key/value interface. Current
adapters use ETS, DETS, partitioned DETS, or Mnesia. Adapter availability is
not a claim of a supported multi-node production topology.

Three storage shapes must not be confused:

| Value | Identity | Mutation |
|---|---|---|
| Definition bytes | Content hash of canonical definition | Immutable while retained |
| Namespace/history chunks | Content hash | Immutable snapshots |
| Branch pointer cell | Name-derived key | Updated by a branch commit |

A branch maps names to content refs. The same content ref can be bound on many
branches, while one stored caller can resolve a named dependency differently
on different branches. `namespace` owns values, history, diff, and merge;
`namespace_codec` owns canonical snapshot/head bytes; `branch_scope` owns
cross-branch read/retraction scope.

Content is verified before CAS admission and checked again where execution
requires it. `publish`, admitted MCP writes, and `pkg install` enforce evidence;
sync verifies that received bytes match their refs, while `run` enforces the
execution evidence policy. Explicit retraction and purge can remove content
when dependency/branch rules permit it, so the codebase is not an unconditional
append-only log.

## Effects and bounded evaluation

The surface language supports abilities, handlers, `do`, `handle`, holes,
guards, and `use`. `gleamunison_effets.erl` owns the process-local ability
handler stack. `Do` dispatches to the selected frame; this is not a general
serializable-continuation or live-process-migration implementation.

Evaluation runs behind execution-profile admission and resource budgets.
The evaluator owns its scope and descendant cleanup on timeout/cancellation.
These controls reduce in-process risk; they do not isolate the host kernel,
filesystem, or VM from hostile native code.

`local` and `authenticated-remote` execution use the in-process evaluator.
Transport-facing `untrusted-execution` admission refuses because no approved
external executor is configured. Direct host capabilities such as `file-read`
and `http-get` remain separate from application `Db` writes and must not be
described as covered by that one effect.

## Durable agent read model

MCP and HTTP use the supervised web session rather than independent immutable
bootstrap catalogs. `agent_read_model` projects the selected durable branch
and CAS into entries that retain actual content refs, stored types, origins,
and branch metadata.

Scratch definitions are an explicit session overlay. They shadow durable names
without changing the branch or CAS. MCP is a bounded gateway over the session's
snapshots; it does not promote scratch or maintain a second session authority.
Stored dependencies are loaded before scratch evaluation.

The design and its rejected source-reconstruction shortcut are recorded in
[ADR 0068](adr/0068-durable-agent-read-model.md).

## Admitted writes and bounded generation

`agent_publish` accepts source, not a caller-selected hash, branch, or storage
path. Its pipeline is:

```text
source → definitions-only load → elaboration → tests/evidence
       → trust turnstile → CAS insert + selected-branch binding
       → fresh durable snapshot + preserved scratch overlay
```

The supervised session serializes publication. Untrusted execution is refused
before storage opens. A successful receipt contains real content refs that the
same runtime can execute; see [ADR 0070](adr/0070-admitted-agent-writes.md).

`agent_generate` composes the existing modules instead of creating a parallel
write system:

- `prompt` stores a checked content-addressed template.
- `schema_printer` renders the requested and inferred type shapes.
- `sap` parses bounded near-miss candidate envelopes.
- `generation_loop` retries with feedback within hard size/attempt limits.
- `agent_publish` performs every admission.
- `patch` reports direct stored dependents; it does not fabricate source or
  automatically regenerate applications.

The provider is server-owned. Candidate source, inferred type, evidence, and
branch admission are checked independently. Exhaustion leaves branch bindings
unchanged, although an immutable prompt may remain as an audit artifact.
A request without `target` handles one target term. An explicit `target`
names the definition that owns the requested signature and permits admitted
helper definitions in the same candidate; every definition receives a content
ref. This is not arbitrary multi-definition application synthesis. See
[ADR 0072](adr/0072-bounded-agent-generation.md) and
[ADR 0073](adr/0073-target-selected-helper-generation.md).

## Application state and Datalog

Application facts are not code CAS. The typed `Db` ability currently provides
`transact`, exact `get`, and exact `find` over text-valued EAV facts.
`gleamunison_app_db` supervises one durable journal, `application.dets`, beside
the configured code store. Each valid transaction is one journal record;
restart derives current state and the next transaction id by replay.

This V1 is deliberately smaller than a general database server. It has no
ambient HTTP database-write API, arbitrary Datalog joins through `Db`, or
multi-node application-store claim. See
[ADR 0069](adr/0069-durable-db-ability.md).

The separate `gleamunison_datalog/` engine is written in Gleamunison's own
S-expression language. It supplies immutable EAV indexes, transactions,
queries, temporal operations, rules, graph/search functions, and an in-process
transactor model. It is not automatically the durable `Db` journal.

## Services and admitted application routes

HTTP and MCP run under OTP supervisors. Readiness and observability expose
storage, process, queue, and bounded-resource state. `mcp_session`,
`mcp_write`, and `session_refresh` separate RPC, admission, and snapshot
refresh responsibilities.

`POST /app/:name` and `POST /app/ref/:content-ref` execute only admitted
content on the server-selected branch. `app_path` performs strict segment
decoding; `app_route` resolves targets and validates bounded JSON arguments;
`app_response` renders bounded JSON results; `run_ref` remains the execution
and evidence authority. Scratch and arbitrary unbound CAS content are not
routes. See [ADR 0071](adr/0071-admitted-app-routes.md).

## Sync, security, and deployment

`sync`/`sync_types` define the protocol, with TCP and Erlang-distribution
FFI at the transport boundary. TCP v2 uses authenticated handshake/replay
controls. These mechanisms do not supply TLS for HTTP, secure an Erlang
cluster automatically, or establish a multi-tenant trust boundary.

The verified deployment classification is **authenticated single-node
service**. Bind/profile checks, request authorization, evidence policy,
execution budgets, bounded observability, and LLM controls are separate
boundaries with separate proofs. TLS/mTLS, an OS/container executor, complete
package provenance/revocation, live migration, and production multi-node
isolation are not claimed.

See [Deployment profiles](operations/deployment-profiles.md),
[Production operations](OPERATIONS.md), and
[ADR 0067](adr/0067-production-boundaries.md). Where an older ADR records a
pending contract, current source and the latest verification witness decide
what is implemented.

## Artifact and verification

`build_escript.sh` packages the runtime and BEAM dependencies into an escript.
The Erlang VM is a runtime dependency. Artifact contents, declared version,
Datalog inclusion, test exclusion, and clean-build reproducibility are gate
checks; artifact size is not an architectural invariant.

Use `gleam test`, `gleam format --check src test`, the playbook runner, and
`bb scripts/verify_production_boundaries.clj` for their distinct jobs.
`docs/operations/verification-matrix.md` and the latest dated witness record
what was actually proved. Local macOS/OTP results do not stand in for every
configured hosted OTP/OS matrix leg.

## Invariants worth preserving

1. A content ref identifies canonical content and type, never a mutable name.
2. Scratch never becomes durable without the ordinary evidence/admission path.
3. Generation proposes source; publication alone admits it.
4. Code CAS, application facts, and provider credentials have independent
   lifecycles and owners.
5. A name route resolves only the selected branch; a ref route must also be
   bound there.
6. Capability denial, request authentication, transport encryption, and OS
   isolation answer different questions and cannot substitute for one another.
7. Dated evidence reports measurements; current documentation reports
   contracts.
