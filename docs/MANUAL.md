# Gleamunison reference manual

Gleamunison is a content-addressed language runtime with algebraic effects,
implemented in Gleam on the Erlang BEAM. This manual covers the current user
surface. [Architecture](ARCHITECTURE.md) explains internals;
[Operations](OPERATIONS.md) covers deployment; dated witnesses record tests.

## 1. Identity and code

A definition's identity is SHA256 over its canonical term **and inferred type**.
Names are mutable metadata bound to immutable content refs. A branch selects
which content ref a name resolves to; it does not change that content's hash.

Compilation produces hash-named BEAM modules. Old and new definitions can
coexist, but application upgrade semantics, evidence, and deployment authority
remain separate from code loading.

Code admission and execution are different gates:

- `publish`, admitted MCP writes, and `pkg install` enforce evidence/trust.
- Sync verifies that transferred bytes match their content refs.
- `run` and `/app` enforce execution evidence, selected-branch resolution,
  profile admission, and evaluation budgets.

Scratch definitions in an agent/HTTP session are not admitted content. They
remain an explicit overlay until source passes the ordinary publication path.

## 2. Toolchain and CLI

Build with Gleam 1.19.1 on Erlang/OTP 27, 28, or 29:

```sh
gleam deps download
./build_escript.sh
./gleamunison_escript --help
```

The escript includes the application and BEAM dependencies but **requires
Erlang/OTP at runtime**. Gleam is not needed to run the packaged artifact.

Common commands:

```sh
./gleamunison_escript repl [file.lisp ...]
./gleamunison_escript server 8080
./gleamunison_escript verify file.lisp
./gleamunison_escript test file.lisp
./gleamunison_escript publish file.lisp
./gleamunison_escript run <content-ref> [args...] [--json]
./gleamunison_escript run <content-ref> --inspect
./gleamunison_escript find <intent> [--load file.lisp] [--limit N]
./gleamunison_escript mcp 8099
./gleamunison_escript lsp
```

`--help` is the authoritative command list, including evidence, replay,
packages, sync, formatting, Datalog, watch, and playbook-level commands.
`run --json` executes and renders JSON; `run --inspect` reads exports without
calling the definition.

The default store is `.gleamunison/store.dets`. `GLEAMUNISON_STORE_DIR` selects
another directory and must be absolute when explicitly set.
`GLEAMUNISON_BRANCH` selects the namespace, defaulting to `main`.

`unpublish` retracts a branch name and removes bytes only when branch and
dependency rules permit. `purge <hash>` is a dry run until `--yes`; both avoid
leaving dependent content or another live branch pointing at missing bytes.
Use `log content`, `log exec`, or `log all` to inspect the durable journals.

## 3. Surface language

The parser accepts S-expressions. Typical forms include:

```lisp
42
"hello"
(1 2 3)
(let x 42 (add x 1))
(lam x (add x 1))
(define answer 42)
```

The elaborator resolves names, assigns lexical variable indices, checks
abilities, and infers types before canonical identity is computed. The AST
supports terms, type declarations, abilities, tagged construction, patterns,
guards, effects, holes, and `use` desugaring. See `src/gleamunison/ast.gleam`
for constructors rather than relying on a manually maintained count.

### Guards

Match cases may carry guard expressions, emitted as Erlang guards:

```lisp
(match x ((n (< n 5)) small)
          (_ other))
```

Only guard-safe operations are valid in that position.

### Holes

`?` is a typed incomplete expression. It compiles to a loud runtime error;
it is not a promise of automatic live programming or continuation migration.

### `use`

`use` is lambda-passing sugar:

```lisp
(use x <- call body)
;; conceptually: call (lam x body)
```

### Labeled arguments and type aliases

`(fn* ((x default) ...) body)` provides curried-lambda/default sugar.
Surface type aliases and public aliases elaborate through the ordinary type
pipeline; visibility does not create a second content identity system.

## 4. Effects and host capabilities

`Do` dispatches an operation to the current process-local ability handler.
`Handle` installs a handler for a computation. The runtime validates operation
shapes and effect requirements, but this stack is not a general serializable
continuation API.

Builtins include ambient process/IO operations such as `spawn`, `self`, `send`,
`recv`, `sleep`, `now`, `read_line`, `json-parse`, `http-get`, and `file-read`.
These host capabilities are distinct from the application `Db` effect and are
not made safe for hostile code merely by running in a BEAM process.

The bootstrap vocabulary also contains a `Remote` ability declaration. Do not
infer a supported location-transparent compute, live migration, or serializable
continuation implementation from that declaration. Current production claims
are single-node; sync and process primitives do not change that boundary.

## 5. Storage and synchronization

`StorageAdapter` supports ETS, DETS, partitioned DETS, and Mnesia primitives.
Its trusted key/value interface is not itself an untrusted CAS write API:
`storage.insert_content` verifies immutable content, while mutable branch
pointers use a separate name-derived key.

A branch pointer selects an immutable namespace snapshot. Namespace/history
chunks are content-addressed. Application `Db` facts and operational logs have
their own mutable/durable lifecycles.

Sync supports framed TCP and Erlang-distribution transports. TCP v2 uses an
authenticated handshake and replay controls. Execution does not fetch missing
peers implicitly; transfer the dependency closure explicitly before running.
No supported multi-node production cluster is claimed.

## 6. Datalog and application Db

The self-hosted engine under `gleamunison_datalog/` provides immutable EAV
indexes, transactions, Datalog queries, temporal operations, recursive rules,
graph functions, BM25/vector search, and an in-process transactor model.

The durable application `Db` ability is intentionally smaller:

- `Db.transact(assertions, retractions)` commits one journal transaction.
- `Db.get(entity, attribute)` performs an exact read.
- `Db.find(attribute, value)` performs an exact match.

Facts use the EAV pair shape with text values. `application.dets` is the durable
journal beside the configured code store. Current `Db` does not expose arbitrary
Datalog joins, temporal queries, a general HTTP database API, or multi-node
state replication.

## 7. Agent interfaces

MCP and HTTP share the supervised durable/scratch read model. Discovery returns
actual content refs separately from name refs; stored terms are not turned into
fabricated source for display or identity.

`agent_publish` accepts `{source: string}` and returns admitted content refs.
It does not accept a storage key, branch, store path, evidence bypass, or
provider credential. Untrusted execution refuses before storage opens.

`agent_generate` accepts a bounded template/variables/signature/attempt request
with an optional non-empty `target`. Without `target`, one target term is
required. With `target`, the candidate may define that target plus helper
terms; the named target's inferred type must match the requested signature.
The server owns provider configuration. SAP may repair a near-miss candidate
envelope, but inferred type, tests, signed evidence, trust, CAS, and selected-
branch admission are checked by the ordinary publication path. Exhaustion does
not add branch bindings. Helper bundles are explicit and receipted; they are
not arbitrary multi-definition application synthesis.

## 8. HTTP application routes

```text
POST /app/:name
POST /app/ref/:content-ref
```

The body is empty or exactly `{"args":[...]}` with at most eight bounded JSON
values. Named routes resolve the selected branch; ref routes additionally
require that ref to be bound there. Scratch and arbitrary unbound CAS content
return 404.

The response contains the real `ref`, selected `branch`, and bounded JSON
`value`. Evidence, profile, authorization, dependency loading, and evaluation
remain enforced. See [ADR 0071](adr/0071-admitted-app-routes.md).

## 9. Services and libraries

- HTTP client, JSON, DateTime, and crypto Gleam modules live under
  `src/gleamunison/`.
- Use the `filepath` Hex package; the local Gleamunison filepath wrapper and
  template module were removed.
- Logging, metrics, readiness, traces, supervision, and several transport
  boundaries are Erlang-side modules, not removed features and not necessarily
  wrapped by a same-named Gleam module.
- LSP uses stdio; see [LSP](LSP.md).
- In-process logs/traces/metrics are bounded caches, not durable telemetry.
  See [Observability](operations/observability.md).

## 10. Verification and errors

```sh
gleam test
gleam format --check src test
gleam check --target erlang
bb scripts/run_playbook_tests.clj
bb scripts/verify_production_boundaries.clj
```

The unit/integration suite, playbook conformance, artifact contract, and
production-boundary battery are different proofs. Playbook exclusions are not
passing tests; local OTP results are not the entire hosted CI matrix.

Parser/elaboration errors retain structured codes such as `P001` and `E001`
where the owning modules define them. CLI execution uses nonzero exits for
refusals and resolution failures; stderr carries diagnostics so successful
`run --json` stdout remains machine-readable.

For library integration, target Erlang and read the actual public signatures
in `ast`, `codebase`, `pipeline`, `loader`, and `run_ref`. Content construction,
loading, evidence, and execution have distinct contracts; do not reduce them
to a guessed `empty()`/`ensure_loaded()` snippet from an older manual.
