# Production-boundary verification matrix

This matrix maps a current boundary claim to its executable proof. It is a
guide to what to run, not a claim that a command ran in this checkout. Dated
witnesses under `docs/verification/` record actual source/artifact revisions,
exit codes, durations, and exclusions.

Most domain suites run through `gleam test`; the integrated
`bb scripts/verify_production_boundaries.clj` battery separately covers format,
artifact, CLI, HTTP, release, playbook, and related process contracts.

| Boundary | Runnable proof | What green means / does not mean |
|---|---|---|
| Loopback liveness and readiness | `test/production_readiness_test.gleam`; `curl /api/live` and `/api/ready` on a local server | Public liveness is distinct from required-resource readiness; a readiness 503 names failed checks. It is not a full CAS or backup audit. |
| Non-loopback bind gate | `test/transport_auth_test.gleam` | Missing authenticated-remote profile/admin token refuses. Token/profile presence does not prove TLS or proxy health. |
| HTTP/MCP identity and scopes | `test/transport_auth_test.gleam`; HTTP route integration tests | Public, data-read, data-write, and admin scopes are separated. No external proxy identity or TLS is inferred. |
| Authenticated TCP sync | `test/sync_auth_test.gleam`, `sync_accept_test.gleam`, `sync_test.gleam` | Missing/wrong proof, replay, oversized frames, and invalid content are refused; valid authenticated sync works. This is not a native-TLS or Erlang-cluster security proof. |
| Content identity and admission | `test/trust_policy_test.gleam`, `codebase_test.gleam`, `definition_codec_test.gleam`, `storage_test.gleam` | Content bytes bind to canonical identity; tampering and malformed/untrusted input refuse. Integrity alone is not provenance or semantic correctness. |
| Branch/pointer separation | `test/namespace_test.gleam`, `cli_branch_scope_test.gleam`, `retraction_branch_scope_test.gleam`, agent/read-model and route tests | Mutable pointers are not content refs; wrong/missing branches and stale overlays are visible. This is not distributed branch consensus. |
| Evidence and key policy | `test/trust_policy_test.gleam`, `evidence_test.gleam`, `evidence_io_test.gleam`, `signed_cli_evidence_test.gleam` | Signer/subject/policy and rotation/revocation/expiry rules are enforced at the documented gates. The production runtime's configured signer boundary remains narrower than library overlap helpers. |
| Evaluation scope and budgets | `test/execution_scope_test.gleam`, `evaluation_timeout_test.gleam`, `resource_policy_test.gleam` | In-process scopes have deadlines, resource limits, and descendant cleanup. This is not kernel/OS isolation. |
| External executor refusal | `test/sandbox_boundary_test.gleam`, admitted-write and `/app` profile tests | Transport-facing untrusted execution refuses before work/storage when no approved executor exists. It does not prove an external executor exists. |
| Resource saturation | `test/resource_policy_test.gleam`, `observability_recovery_test.gleam` | Request/worker/frame/cache/cardinality limits fail closed or saturate visibly. In-process caches are not durable telemetry. |
| Crash/restart and drain | `test/observability_recovery_test.gleam`, HTTP/service tests | Supervised workers recover and listeners drain without false success. A process restart is not by itself a store-restore proof. |
| Durable agent read model | `test/agent_read_model_test.gleam`, MCP/session refresh tests | Durable and scratch entries stay distinct and services converge on the selected branch. Scratch is not silently admitted. |
| Admitted writes and generation | `test/agent_publish_test.gleam`, `generation_loop_test.gleam`, `generation_request_test.gleam`, `mcp_http_test.gleam` | Source/candidates pass inferred-type, evidence, trust, and branch admission; invalid/exhausted generation does not add bindings. Fixture success is not model-quality evidence. |
| Durable application Db | `test/db_ability_test.gleam`, application route/integration tests | Typed facts commit to the journal and survive owner restart. V1 exact EAV reads are not full Datalog or multi-node state replication. |
| Admitted `/app` routes | `test/app_route_test.gleam`, `app_route_http_test.gleam` | Only selected-branch admitted content executes with bounded JSON; scratch/unbound CAS/untrusted work refuses. |
| Artifact contract | `./build_escript.sh`; `bash scripts/test_artifact.sh` | Packaged version/dependencies/assets match the declared contract and test modules are absent. Existence of an old artifact is not a fresh build proof. |
| Release reproducibility | `bb scripts/test_release_contract.clj` | Two clean builds of the same source are byte-identical and the release contract passes. It is not a hosted CI-matrix receipt. |
| Upgrade/rollback | `bb scripts/test_upgrade_rollback.clj` | The tested prior/current artifact and corrupt-install recovery paths are reversible and loud. A new schema still needs an explicit migration design. |
| CLI truth and errors | `bb scripts/test_cli_truth.clj`; `bb scripts/test_cli_errors.clj` | Help, process exits, stderr/stdout, and bad invocations match the shipped CLI. It is not an external-provider test. |
| HTTP static boundary and dashboard | `bash scripts/test_http_boundary.sh`; `bun scripts/test_dashboard_safety.mjs` | Traversal/static and hostile-markup cases stay bounded/inert. This is not a complete application security audit. |
| Playbook conformance | `bb scripts/run_playbook_tests.clj`; `bb scripts/test_parser.clj`; `bb scripts/test_playbook_runner.clj` | Parsed executable cases pass, exclusions stay pinned, and crash/timeout/stale policy fails closed. Exclusions are not passes. |
| LSP transport | `bb scripts/test_lsp_stdio.clj` | Stdio framing, UTF-8, and malformed-input behavior pass. It is not an editor-specific certification. |
| Integrated witness | `bb scripts/verify_production_boundaries.clj` | Every required integrated battery exited 0 and the witness records its scope/exclusions. Domain tests above are included through `gleam test`; this table itself does not execute anything. |

## Classification

The current dated witness reports `authenticated-single-node-service` for its
tested artifact/configuration. That label does not assert native TLS, external
untrusted execution, safe multi-tenancy, or a supported multi-node deployment.
Those require separate implementation and evidence, not a documentation rename.

Local macOS/OTP results do not prove every OTP 27/28/29 × Ubuntu/macOS hosted
CI leg. Record the CI result separately from the local witness.

## Evidence format

A useful witness records:

- date/time in EAT and the source revision;
- artifact hash where applicable;
- exact command, profile/environment shape, and no secret values;
- exit code and bounded relevant output;
- manual checks, skips, exclusions, and unresolved risks;
- whether any push, tag, publish, merge, deployment, or release occurred.

Keep current contracts in this matrix and measured results in dated witnesses.
Do not change an old witness's numbers to describe a newer tree.
