# ADR 0067: Production boundaries and execution profiles

- **Status:** Accepted as the release contract; enforcement is pending in plan tasks 2–8
- **Date:** 2026-10-20 (EAT)
- **Tracking:** Bankai `bk-c7bb`; GitHub issue [#25](https://github.com/moneyacademyKE/gleamunison/issues/25)
- **Related:** [ADR 0001](0001-content-addressed-identity.md), [ADR 0021](0021-runtime-tradeoffs-and-robustness-safeguards.md), [ADR 0065](0065-verified-cas-admission.md), [ADR 0066](0066-bounded-readiness-and-metrics.md)

## Context

The v3.23.0 hardening pass closed the ten defects recorded in the 2026-10-19 production-gap audit. That work made malformed input, false-green verification, CAS identity, and the HTTP/MCP lifecycle more honest. It did not make a BEAM process an operating-system sandbox, nor did it define the contract for remote exposure, package provenance, resource exhaustion, recovery, compatibility, or LLM privacy.

The dangerous failure mode is a **profile confusion**: a local research runtime is bound or configured as if it were an authenticated, multi-tenant, untrusted-code service. A capability handler, process scope, signed evidence record, or TLS connection is useful evidence of one boundary; none is permission to claim the others.

This ADR freezes the vocabulary and release boundary before implementation. It is a contract, not a claim that every control is already present in the binary.

## Decision

### 1. Keep the identities and assets separate

The following values have different owners and must not be folded into one content hash or one mutable record:

| Object | Meaning | Mutability | Trust rule |
|---|---|---|---|
| Definition content ref | Hash of canonical definition structure and type metadata | Immutable | Recompute before admission and before execution |
| Definition bytes | Recoverable runtime encoding for one content ref | Immutable after admission | Verify bytes bind to the requested ref |
| Branch pointer | Human/workflow name to a root ref | Mutable | Bind the stored pointer to its requested branch and journal updates |
| Package manifest | Versioned dependency closure and package metadata | Immutable per release | Verify subjects and dependencies before install |
| Evidence | Attestation about a subject, dependencies, runner, and result | Append-only by subject | Require signer, expiry/revocation, and production policy |
| Signer identity | Key/person/service allowed to attest | Rotatable | Keep key identity separate from the content subject |
| Deployment identity | Node/service/profile identity | Runtime-scoped | Authenticate requests and sync peers; never infer it from a branch name |
| Request/session identity | Caller and authorization scope for one operation | Short-lived | Bind authorization to the request/session and prevent replay |
| Secret | Provider, signing, TLS, or executor credential | External/private | Never place in source refs, evidence payloads, or telemetry |
| Telemetry | Bounded operational observation | Redacted/retained | No secret or unrestricted prompt/code capture |

A package name, branch pointer, signer, or deployment identity is therefore not an input to a definition content hash. A valid hash proves content identity; it does not prove authorization, authorship, safety, or correctness.

### 2. Use three explicit deployment profiles

The profile is selected at startup and is part of the observable release contract. The implementation may choose a compatible configuration surface, but it must preserve these names and refusal semantics:

| Profile | Intended use | Default trust boundary | Required startup behavior |
|---|---|---|---|
| `local` | One operator, one node, loopback development/research | Local OS user and local files | Bind loopback by default. Refuse a non-loopback bind unless the authenticated-remote contract is active. |
| `authenticated-remote` | An explicitly operated remote single-node service | Authenticated client, encrypted transport, authorized scopes | Refuse startup without TLS/mTLS or an explicitly configured authenticated reverse-proxy contract, request authorization, and authenticated sync policy. |
| `untrusted-execution` | Code supplied by a party that is not trusted with the node | Approved external OS/container executor | Refuse startup or execution unless an approved OS/container executor, resource policy, cancellation path, and redaction policy are configured. A BEAM process scope is not sufficient. |

`local` is the only profile that may remain convenient by default. The other two are opt-in and fail closed. No profile may silently downgrade to a weaker profile when a required control is absent.

### 3. Define trust zones

The implementation and its tests must name the crossing being protected:

1. **Operator zone:** local configuration, release artifact, and administrative actions.
2. **Runtime zone:** the Gleamunison VM, supervisors, stores, code loader, and bounded metrics.
3. **Client zone:** HTTP/MCP callers and sync peers, which are untrusted until authenticated and authorized.
4. **Execution zone:** evaluated definitions and their descendants; in `untrusted-execution`, this zone belongs outside the VM in an approved OS/container executor.
5. **Provider zone:** LLMs, external HTTP services, key stores, and signing systems; their responses are data, not instructions.

A capability denial protects an operation inside the runtime zone. It does not authenticate a client, isolate the VM from the host, or prove that a provider response is safe.

### 4. Make refusal a first-class result

The following are startup or admission refusals, not warnings:

- non-loopback binding without the authenticated-remote transport and authorization contract;
- remote sync without authenticated peer identity, bounded frames, and replay/session binding;
- `untrusted-execution` without the approved external executor and an enforceable resource policy;
- production package/evidence admission without canonical subjects, signer policy, and revocation/expiry checks;
- missing or invalid resource limits where a boundary claims a limit;
- secret-bearing values appearing in logs, metrics, evidence, traces, or durable transcripts;
- a failed recovery, migration, compatibility, or rollback proof being reported as release-ready.

There is no “best effort” production profile. Diagnostic mode may explain a refusal, but it must retain a non-zero/failed machine-readable result.

### 5. Attach one proof to every boundary

The release record must link each claim to a runnable command, its exit code, the artifact/source revision, and the expected refusal or success result. The verification matrix in `docs/operations/verification-matrix.md` is the index. A green unit suite alone cannot certify a profile boundary.

The minimum final classification is:

- **Safe local research runtime:** loopback-only, local trust, no claim of untrusted-code isolation.
- **Authenticated single-node service:** remote access only with encrypted/authenticated transport and scopes; execution remains trusted unless the external executor proof also exists.
- **Untrusted-code production platform:** forbidden as a label until OS/container isolation, identity/trust, resource, recovery, compatibility, and privacy evidence all pass.

## Consequences

- Operators get a small vocabulary instead of one vague “production mode.”
- Local development stays simple, but accidentally exposing a local node becomes a loud refusal rather than a silent downgrade.
- Remote encryption and authorization are separate obligations. TLS without scopes is insufficient; scopes without authenticated transport are insufficient.
- Signed evidence and content identity remain separate. A signer can attest to a subject, but cannot change that subject or turn a branch pointer into immutable content.
- In-process supervision and cancellation remain valuable containment layers. They must not be advertised as a complete sandbox.
- The plan proceeds in order: execution boundary, transport, trust/storage, resources/observability, compatibility/recovery, LLM policy, then the integrated witness. Remote untrusted execution remains disabled until the earlier proofs pass.

## Alternatives rejected

- **One universal production flag:** rejected; it complects binding, authorization, signatures, quotas, and OS isolation and makes partial configuration look complete.
- **Treat a BEAM process tree as a sandbox:** rejected; the VM and its FFI still share the host boundary.
- **Use branch or package names as security identity:** rejected; mutable names are not immutable content or authenticated principals.
- **Treat a green test count as a release proof:** rejected; process boundaries, artifact contents, recovery, and refusal paths require executable probes.
- **Silently fall back to unsigned or unauthenticated mode:** rejected; absence of a trust control is a refusal condition.

## Scope and non-goals

This ADR does not implement TLS, mTLS, an OS executor, signatures, quotas, a durable telemetry exporter, or LLM redaction. Those are the subsequent plan tasks. It does not authorize a tag, Hex publish, merge, deployment, or public production claim.

**Rich Hickey check:** one policy owner per boundary, one explicit refusal path, and one proof index. The rejected alternative is a universal “production” abstraction that complects unrelated authority and makes the system harder to reason about.
