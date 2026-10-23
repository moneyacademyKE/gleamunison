# Trust and key rotation

**Date:** 2026-10-20 (EAT)
**Tracking:** Bankai `bk-9154`

Gleamunison evidence is HMAC-signed. This document owns the lifecycle of the keys behind those signatures: how trust is granted, rotated, expired, and revoked. The policy data lives in `src/gleamunison/trust.gleam`; signature mechanics live in `src/gleamunison/evidence.gleam`. Neither file alone is the answer — a valid signature from a revoked key must still refuse.

## Concepts

| Concept | Meaning |
|---|---|
| Signer | `evidence.Signer(id, secret)` — secret never serialized into records |
| Key state | `Active(since, until)` or `Revoked` |
| Trust policy | Ordered list of trusted keys with states |
| Admission | Signature match AND key state admits the record timestamp |

A signature proves the record came from a key. The trust policy proves the key was allowed to speak at that time. Both are required.

## Configuration

The policy is data, and the four environment variables below are how an
operator sets it without recompiling. Absent means no limit, so an existing
store keeps verifying until you say otherwise.

| Variable | Effect | Default |
|---|---|---|
| `GLEAMUNISON_EVIDENCE_SIGNING_KEY` | the secret whose HMAC signs records | required for production |
| `GLEAMUNISON_EVIDENCE_KEY_SINCE` | unix seconds the key becomes valid | `0` |
| `GLEAMUNISON_EVIDENCE_KEY_UNTIL` | unix seconds the key stops being valid | no expiry |
| `GLEAMUNISON_EVIDENCE_KEY_REVOKED` | `1`/`true`/`yes` revokes the key outright | unset |
| `GLEAMUNISON_EVIDENCE_MAX_AGE_SECS` | refuse attestations older than this | `0` (no limit) |

The signer id is `env:GLEAMUNISON_EVIDENCE_SIGNING_KEY`, which is what appears
in a refusal: `key_expired:env:GLEAMUNISON_EVIDENCE_SIGNING_KEY`.

Rotation with these variables is two settings, not a code change: raise
`_KEY_SINCE` to the cutover time with the new secret, then set `_KEY_UNTIL` on
the old one. Revocation is `_KEY_REVOKED=1`, effective immediately and without
touching a single evidence record — which is the point, since records are
content-addressed and cannot be edited.

`evidence <hash>` prints the effective policy, so an operator can see what is
being enforced rather than inferring it from an exit code:

```
policy: env:GLEAMUNISON_EVIDENCE_SIGNING_KEY: active since 0, no expiry; no attestation age limit
test: admitted by the policy
io: refused (no_record:io)
```

## Rotation procedure

1. Generate the new signer; distribute its secret out of band.
2. Add it to the policy with `since = rotation_time - overlap` and a long `until`.
3. Update the old key's `until = rotation_time`. The overlap window lets in-flight records signed by either key verify.
4. After the old key's `until` passes, remove it from the policy entirely.

Rotation overlap is tested in `test/trust_policy_test.gleam`: both keys admit during the window, the old key refuses after. `trust.verified/4` keeps trying
the remaining records of the same kind, so a store holding records from both
keys admits through the overlap rather than refusing on the newest one.

## Revocation

Set the key's state to `Revoked`. All records signed by it refuse immediately, regardless of timestamp. Use revocation for compromise; use expiry for routine rotation.

## Expiry

`Active(since, until)` — records with `ts >= until` refuse with `key_expired`. Records with `ts < since` refuse with `key_not_yet_valid`. The record timestamp is part of the signature, so backdating a record changes its signature and fails verification anyway.

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

A bool said "false" to all of these. The name is the point: `key_expired` means
rotate, `no_record` means run the tests, `signature_mismatch` means something is
wrong.

## What trust is not

- Trust is not content identity. A content ref proves bytes; a signer proves attestation. Neither substitutes for the other.
- HMAC possession is not public provenance. Anyone with the secret is the signer; keep secrets out of logs, transcripts, evidence payloads, and telemetry.
- An expired key does not invalidate history — it invalidates new claims. Old records remain verifiable if their timestamps sit inside the key's original window.
