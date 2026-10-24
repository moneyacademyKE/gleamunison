# Trust and key rotation

**Date:** 2026-10-24 (EAT)
**Tracking:** Bankai `bk-5296`

Gleamunison evidence is HMAC-signed. This document owns the lifecycle of the
single signer configured by the production environment: how trust is granted,
rotated, expired, and revoked. The policy data lives in
`src/gleamunison/trust.gleam`; signature mechanics live in
`src/gleamunison/evidence.gleam`. Neither file alone is the answer — a valid
signature from a revoked key must still refuse.

## Concepts

| Concept | Meaning |
|---|---|
| Signer | `evidence.Signer(id, secret)` — secret never serialized into records |
| Key state | `Active(since, until)` or `Revoked` |
| Trust policy | The production policy contains one configured signer; library policies can contain more |
| Admission | Signature match AND key state admits the record timestamp |

A signature proves the record came from a key. The trust policy proves the key
was allowed to speak at that time. Both are required.

## Production configuration

The shipped production entry point reads one signer secret and one state window.
Absent values mean no limit, so an existing store keeps verifying until an
operator says otherwise.

| Variable | Effect | Default |
|---|---|---|
| `GLEAMUNISON_EVIDENCE_SIGNING_KEY` | the one secret whose HMAC signs records | required for production |
| `GLEAMUNISON_EVIDENCE_KEY_SINCE` | unix seconds the key becomes valid | `0` |
| `GLEAMUNISON_EVIDENCE_KEY_UNTIL` | unix seconds the key stops being valid | no expiry |
| `GLEAMUNISON_EVIDENCE_KEY_REVOKED` | `1`/`true`/`yes` revokes the key outright | unset |
| `GLEAMUNISON_EVIDENCE_MAX_AGE_SECS` | refuse attestations older than this | `0` (no limit) |

The signer id is `env:GLEAMUNISON_EVIDENCE_SIGNING_KEY`, which is what appears
in a refusal: `key_expired:env:GLEAMUNISON_EVIDENCE_SIGNING_KEY`.

Production supports **one configured signer at a time**. Replacing
`GLEAMUNISON_EVIDENCE_SIGNING_KEY` is a cutover, not a multi-key overlap: the
old and new secrets cannot both be accepted by `production_policy()` through
the current environment contract. The `TrustPolicy` type can represent
multiple keys for library callers and tests, but that is not an operator-facing
configuration surface.

`evidence <hash>` prints the effective policy, so an operator can see what is
being enforced rather than inferring it from an exit code:

```
policy: env:GLEAMUNISON_EVIDENCE_SIGNING_KEY: active since 0, no expiry; no attestation age limit
test: admitted by the policy
io: refused (no_record:io)
```

## Production cutover procedure

1. Generate the new signer and distribute its secret out of band.
2. Choose the cutover timestamp. Set `GLEAMUNISON_EVIDENCE_KEY_SINCE` to that timestamp and replace `GLEAMUNISON_EVIDENCE_SIGNING_KEY` with the new secret.
3. Restart or roll the production process so all new attestations use the new signer.
4. Verify a fresh `evidence <hash>` report and the expected signer id before admitting new content.
5. If the old signer was compromised, set `GLEAMUNISON_EVIDENCE_KEY_REVOKED=1` for the old-key deployment or retire that deployment immediately. Do not claim zero-downtime overlap from the current one-key environment.

If uninterrupted overlap is a requirement, it needs a separately specified
production configuration contract: signer identifiers, secret transport,
per-key validity windows, and rollback semantics. Do not encode that contract
as comma-separated environment secrets by convention.

## Library-only overlap behavior

Multi-key overlap is tested in `test/trust_policy_test.gleam`: library callers
can construct a policy where both keys admit during a window and the old key
refuses after it. `trust.verified/4` keeps trying the remaining records of the
same kind, so a store holding records from both keys admits through the overlap.
Those tests prove the library policy, not a production deployment procedure.

## Revocation

Set the configured key's state to `Revoked`. All records signed by it refuse
immediately, regardless of timestamp. Use revocation for compromise; use
expiry for routine cutover.

## Expiry

`Active(since, until)` — records with `ts >= until` refuse with `key_expired`.
Records with `ts < since` refuse with `key_not_yet_valid`. The record timestamp
is part of the signature, so backdating a record changes its signature and
fails verification anyway.

## Refusal vocabulary

| Refusal | Cause |
|---|---|
| `unknown_signer:<id>` | Signer id not in the policy |
| `key_revoked:<id>` | Signer is revoked |
| `key_not_yet_valid:<id>` | Record timestamp before the key's window |
| `key_expired:<id>` | Record timestamp at/after the key's window end |
| `signature_mismatch:<id>` | Record bytes do not match the signer's secret |
| `unsigned_record` | No signer/signature on the record at all |
| `attestation_too_old:<kind>` | Record is older than `GLEAMUNISON_EVIDENCE_MAX_AGE_SECS` |
| `no_record:<kind>` | Nothing of that kind was ever attested |
| `no_passing_verdict:<kind>` | Records exist, but every verdict is a failure |

A bool said “false” to all of these. The name is the point: `key_expired` means
cut over, `no_record` means run the tests, `signature_mismatch` means something
is wrong.

## What trust is not

- Trust is not content identity. A content ref proves bytes; a signer proves attestation. Neither substitutes for the other.
- HMAC possession is not public provenance. Anyone with the secret is the signer; keep secrets out of logs, transcripts, evidence payloads, and telemetry.
- An expired key does not invalidate history — it invalidates new claims. Old records remain verifiable if their timestamps sit inside the key's original window.
