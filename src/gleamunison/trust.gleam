//// Trust lifecycle for signers: rotation windows, expiry, revocation.
////
//// Evidence signatures (HMAC) live in evidence.gleam; this module owns the
//// policy decision of WHETHER a signer is currently trusted. Verification
//// composes the two: a record is admitted only when the signature matches a
//// trusted signer AND that signer's key state admits the record timestamp.

import gleam/list
import gleamunison/evidence.{type Evidence, type Signer}

pub type KeyState {
  /// Usable from `since` until `until` (exclusive). A rotation overlap is two
  /// Active entries: old with `until = T`, new with `since = T - overlap`.
  Active(since: Int, until: Int)
  /// Permanently untrusted, regardless of timestamps.
  Revoked
}

pub type TrustedKey {
  TrustedKey(signer: Signer, state: KeyState)
}

pub type TrustPolicy {
  TrustPolicy(keys: List(TrustedKey))
}

pub fn policy(keys: List(TrustedKey)) -> TrustPolicy {
  TrustPolicy(keys)
}

pub fn active(signer: Signer, since: Int, until: Int) -> TrustedKey {
  TrustedKey(signer, Active(since, until))
}

pub fn revoked(signer: Signer) -> TrustedKey {
  TrustedKey(signer, Revoked)
}

pub type TrustRefusal {
  UnknownSigner(id: String)
  KeyRevoked(id: String)
  KeyNotYetValid(id: String, since: Int)
  KeyExpired(id: String, until: Int)
  SignatureMismatch(id: String)
  UnsignedRecord
}

pub fn refusal_name(refusal: TrustRefusal) -> String {
  case refusal {
    UnknownSigner(id) -> "unknown_signer:" <> id
    KeyRevoked(id) -> "key_revoked:" <> id
    KeyNotYetValid(id, since) -> "key_not_yet_valid:" <> id
    KeyExpired(id, until) -> "key_expired:" <> id
    SignatureMismatch(id) -> "signature_mismatch:" <> id
    UnsignedRecord -> "unsigned_record"
  }
}

/// Pure key-state decision: does this signer id admit a record at `ts`?
pub fn key_admits(policy: TrustPolicy, signer_id: String, ts: Int) -> Result(TrustedKey, TrustRefusal) {
  case list.find(policy.keys, fn(k) { k.signer.id == signer_id }) {
    Error(_) -> Error(UnknownSigner(signer_id))
    Ok(key) ->
      case key.state {
        Revoked -> Error(KeyRevoked(signer_id))
        Active(since, until) ->
          case ts < since {
            True -> Error(KeyNotYetValid(signer_id, since))
            False ->
              case ts >= until {
                True -> Error(KeyExpired(signer_id, until))
                False -> Ok(key)
              }
          }
      }
  }
}

/// Full admission: key state at the record's timestamp AND a signature that
/// matches that signer's secret. Unsigned records are always refused here;
/// local fixtures that need unsigned data use evidence.AllowUnsigned, not a
/// trust policy.
pub fn admit(
  policy: TrustPolicy,
  record: Evidence,
) -> Result(Evidence, TrustRefusal) {
  case record.signer == "" || record.signature == "" {
    True -> Error(UnsignedRecord)
    False ->
      case key_admits(policy, record.signer, record.ts) {
        Error(refusal) -> Error(refusal)
        Ok(key) -> {
          let expected =
            evidence.sign(key.signer, record.subject, record.kind, record.verdict, record.payload, record.ts)
          case evidence.secure_compare_hex(record.signature, expected.signature) {
            True -> Ok(record)
            False -> Error(SignatureMismatch(record.signer))
          }
        }
      }
  }
}
