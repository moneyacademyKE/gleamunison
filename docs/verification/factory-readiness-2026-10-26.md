# Factory readiness acceptance

**Date:** 2026-10-26 (EAT) · **Root task:** `bk-2bae` · **Final verification task:** `bk-f676`
**Code and acceptance HEAD:** `5746656` · **Branch:** `fix/component-audit-2026-10-24`

## Verdict

**Factory-ready for the verified local, authenticated, single-node loop.**
The root path — agent → admitted code → durable app — is closed and exercised
end to end. This is not a deployment, external-provider quality benchmark, or
claim of safe untrusted multi-tenant execution.

## Root acceptance proof

Two real MCP `agent_generate` requests consumed one-shot loopback
[OI]-compatible completions and produced `generated-db-write` and
`generated-db-read`. Both effectful definitions were admitted only after signed
`io` evidence for their exact elaborated content hashes.

1. `POST /app/generated-db-write` returned HTTP 200 and transaction `1`.
2. The test stopped the supervised Db owner.
3. `POST /app/generated-db-read` returned HTTP 200 with `person:1` and `Moe`
   from the recovered `application.dets` journal.
4. Invalid candidates, signature/type mismatches, exhausted attempts, and
   untrusted writes are refused by the same generation/admission pipeline.

The provider transport is real local HTTP; the model output is a deterministic
fixture. No external-provider call was required or claimed.

## Completed factory chain

| Phase | Bankai | Proof / commit |
|---|---|---|
| MCP authority | `bk-0780` | Caller-supplied MCP evaluation obeys execution profile; `a2fd34e` |
| Builtin identities | `bk-9e7e` | Builtin-dependent definitions publish and execute; `551282a` |
| Runnable MCP refs | `bk-56c2` | Content refs are distinct from name refs and runnable; `9b2acf3` |
| Durable read model | `bk-fe15` | Branch/CAS plus explicit scratch overlays; `dc8ed10` |
| Durable Db ability | `bk-2a5c` | Typed Db effects and journal recovery; `4940d90` |
| Admitted agent writes | `bk-effa` | Source-only MCP publication through one admission path; `73e8517` |
| App routes | `bk-f728` | Selected-branch name/ref execution; `d7a4441`, `20a8541` |
| Bounded generation | `bk-6e13` | Prompt/SAP/schema/retry/admission composition; `75083d8`, `3ddc80b` |
| Factory acceptance | `bk-f676` | Generated Db write → owner restart → read; `5746656` |

## Verification battery

- `gleam test`: **736 passed, no failures**.
- Playbook: **934 passed, 0 failed, 0 skipped, 0 timed out, 238 explicitly excluded**.
- Integrated production gate: **PASS, 15 gates** at `5746656`.
- CI contract: **0 failures**.
- Verification contract: **0 failures**.
- Release contract: **PASS**; two clean builds byte-identical, artifact SHA-256
  `133f5ec7da4f9ffb7973ddb718d389d234d00d6ead68e9e7ba2478a396580594`.
- CLI truth: **22 checks passed**; CLI errors: **0 failures**.
- HTTP boundary: exit 0. LSP stdio: **0 failures**.
- Upgrade/rollback, dashboard safety, parser, playbook runner, artifact
  contract, format, Erlang check, LOC ceiling, and diff checks: exit 0.

Machine-readable witness:
[production-boundaries-2026-10-26.md](production-boundaries-2026-10-26.md).
Generation detail:
[bounded-agent-generation-2026-10-26.md](bounded-agent-generation-2026-10-26.md).
Persistent command logs:
`~/.opencrabs/projects/gleamunison/files/factory9-verification/`.

## Boundaries and exclusions

- Production classification is **authenticated-single-node-service**. The
  untrusted profile still requires an approved external OS/container executor;
  in-process capability frames are not an OS sandbox.
- The public generator handles one target term per candidate, scalar/list
  schemas and scalar function signatures. Arbitrary multi-definition helper or
  application generation is not claimed.
- Generated tests are evidence under the existing policy, not semantic proof.
  Effectful code still needs exact-hash signed `io` attestation.
- Patch integration reports direct dependent impact under name-ref runtime
  semantics; automatic stored-source regeneration is not claimed.
- Local verification is macOS arm64 / OTP 29. The OTP 27/28/29 × Ubuntu/macOS
  CI matrix was not run locally and remains a remote/post-push check.
- Playbook exclusions remain explicit, not converted into passing coverage.
- No push, remote publish, release, deploy, tag, or merge occurred.

## Rich Hickey certification

The factory is a composition of existing identity, evidence, storage, effect,
and route contracts. Generation proposes text; it does not acquire a second
write authority. Keeping code CAS, application state, provider configuration,
and admission separate avoids the tempting but brittle “model wrote it, so it
must be runnable” shortcut.
