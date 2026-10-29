//// Trust lifecycle for signers: rotation windows, expiry, revocation.
////
//// This module owns ONE decision: does this evidence count, right now? A
//// signature is necessary but not sufficient — the key that made it must be
//// inside its validity window, must not be revoked, and the attestation itself
//// must not be older than the policy allows. evidence.gleam owns the record and
//// the HMAC; believing it is this module's job, and nobody else's.

import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleamunison/datetime
import gleamunison/env
import gleamunison/evidence.{type Evidence, type Signer}
import gleamunison/storage.{type StorageAdapter}

/// No expiry: an `Active` key with `until = never` is valid until revoked.
pub const never = 9_223_372_036_854_775_807

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

/// How evidence is judged. One type, two variants, and the production
/// constructor can only ever produce the first.
pub type TrustPolicy {
  /// Production: a key whose state admits the record's timestamp, plus a
  /// maximum attestation age in seconds (0 = no limit).
  RequireKeys(keys: List(TrustedKey), max_age_secs: Int)
  /// Fixtures only: an in-memory store holding unsigned records. Never
  /// produced by production_policy, so no CLI path can reach it.
  FixturesOnly
}

pub fn policy(keys: List(TrustedKey)) -> TrustPolicy {
  RequireKeys(keys, 0)
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
  AttestationTooOld(kind: String, ts: Int, max_age_secs: Int)
  EvidenceReadFailed
  NoRecord(kind: String)
  NoPassingVerdict(kind: String, verdict: String)
}

/// A stable machine-readable name. Exit codes tell a script what happened;
/// this tells a human why, and both come from the same decision.
pub fn refusal_name(refusal: TrustRefusal) -> String {
  case refusal {
    UnknownSigner(id) -> "unknown_signer:" <> id
    KeyRevoked(id) -> "key_revoked:" <> id
    KeyNotYetValid(id, _since) -> "key_not_yet_valid:" <> id
    KeyExpired(id, _until) -> "key_expired:" <> id
    SignatureMismatch(id) -> "signature_mismatch:" <> id
    UnsignedRecord -> "unsigned_record"
    AttestationTooOld(kind, _ts, _max) -> "attestation_too_old:" <> kind
    EvidenceReadFailed -> "evidence_read_failed"
    NoRecord(kind) -> "no_record:" <> kind
    NoPassingVerdict(kind, _verdict) -> "no_passing_verdict:" <> kind
  }
}

fn keys_admit(
  keys: List(TrustedKey),
  signer_id: String,
  ts: Int,
) -> Result(TrustedKey, TrustRefusal) {
  case list.find(keys, fn(k) { k.signer.id == signer_id }) {
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

/// Full admission at the current time.
pub fn admit(
  policy: TrustPolicy,
  record: Evidence,
) -> Result(Evidence, TrustRefusal) {
  admit_at(policy, record, datetime.to_unix(datetime.now()))
}

/// Full admission at an explicit time: the signature must match a key whose
/// state admits the record's timestamp, and the record must be young enough.
pub fn admit_at(
  policy: TrustPolicy,
  record: Evidence,
  now: Int,
) -> Result(Evidence, TrustRefusal) {
  case policy {
    FixturesOnly -> Ok(record)
    RequireKeys(keys, max_age_secs) ->
      case record.signer == "" || record.signature == "" {
        True -> Error(UnsignedRecord)
        False ->
          case fresh(record, max_age_secs, now) {
            Error(refusal) -> Error(refusal)
            Ok(_) ->
              case keys_admit(keys, record.signer, record.ts) {
                Error(refusal) -> Error(refusal)
                Ok(key) -> {
                  let expected =
                    evidence.sign(
                      key.signer,
                      record.subject,
                      record.kind,
                      record.verdict,
                      record.payload,
                      record.ts,
                    )
                  case
                    evidence.secure_compare_hex(
                      record.signature,
                      expected.signature,
                    )
                  {
                    True -> Ok(record)
                    False -> Error(SignatureMismatch(record.signer))
                  }
                }
              }
          }
      }
  }
}

fn fresh(
  record: Evidence,
  max_age_secs: Int,
  now: Int,
) -> Result(Nil, TrustRefusal) {
  case max_age_secs {
    0 -> Ok(Nil)
    _ ->
      case now - record.ts > max_age_secs {
        True ->
          Error(AttestationTooOld(
            evidence.kind_name(record.kind),
            record.ts,
            max_age_secs,
          ))
        False -> Ok(Nil)
      }
  }
}

/// Is there evidence of this kind for this subject that the policy admits?
/// Returns the refusal rather than a bare false: "expired key" and "never
/// attested" are different facts and an operator acts on them differently.
pub fn verified(
  adapter: StorageAdapter,
  subject: String,
  kind: evidence.Kind,
  policy: TrustPolicy,
) -> Result(Nil, TrustRefusal) {
  verified_at(adapter, subject, kind, policy, datetime.to_unix(datetime.now()))
}

pub fn verified_at(
  adapter: StorageAdapter,
  subject: String,
  kind: evidence.Kind,
  policy: TrustPolicy,
  now: Int,
) -> Result(Nil, TrustRefusal) {
  use snapshot <- result.try(
    evidence.snapshot(adapter) |> result.replace_error(EvidenceReadFailed),
  )
  verified_in_at(snapshot, subject, kind, policy, now)
}

pub fn verified_in(
  snapshot: evidence.Snapshot,
  subject: String,
  kind: evidence.Kind,
  policy: TrustPolicy,
) -> Result(Nil, TrustRefusal) {
  verified_in_at(
    snapshot,
    subject,
    kind,
    policy,
    datetime.to_unix(datetime.now()),
  )
}

pub fn verified_in_at(
  snapshot: evidence.Snapshot,
  subject: String,
  kind: evidence.Kind,
  policy: TrustPolicy,
  now: Int,
) -> Result(Nil, TrustRefusal) {
  let of_kind =
    evidence.from_snapshot(snapshot, subject)
    |> list.filter(fn(e) { e.kind == kind })
  let newest_first = list.sort(of_kind, fn(a, b) { int.compare(b.ts, a.ts) })
  let passing =
    list.filter(newest_first, fn(e) {
      e.verdict == "pass" || e.verdict == "approved"
    })
  case passing {
    [] ->
      case newest_first {
        [] -> Error(NoRecord(evidence.kind_name(kind)))
        [newest, ..] ->
          Error(NoPassingVerdict(evidence.kind_name(kind), newest.verdict))
      }
    [newest, ..rest] ->
      case admit_at(policy, newest, now) {
        Ok(_) -> Ok(Nil)
        // A rotation overlap admits older records the newest key cannot: the
        // remaining records of this kind are still candidates.
        Error(first_refusal) ->
          case
            list.any(rest, fn(e) { admit_at(policy, e, now) |> result.is_ok })
          {
            True -> Ok(Nil)
            False -> Error(first_refusal)
          }
      }
  }
}

/// Bool form for callers that only branch on the answer. The gate paths use
/// `verified` so they can report the refusal.
pub fn admits(
  adapter: StorageAdapter,
  subject: String,
  kind: evidence.Kind,
  policy: TrustPolicy,
) -> Bool {
  verified(adapter, subject, kind, policy) |> result.is_ok
}

/// The production policy: the env signer plus the window, revocation flag and
/// attestation age it is bound to. Absent variables mean no limit, so an
/// existing store keeps verifying; setting them is how a key is rotated or
/// retired without touching a single evidence record.
pub fn production_policy() -> Result(TrustPolicy, String) {
  use signer <- result.try(evidence.production_signer())
  use since <- result.try(env_int("GLEAMUNISON_EVIDENCE_KEY_SINCE", 0))
  use until <- result.try(env_int("GLEAMUNISON_EVIDENCE_KEY_UNTIL", never))
  use max_age <- result.try(env_int("GLEAMUNISON_EVIDENCE_MAX_AGE_SECS", 0))
  let state = case env_flag("GLEAMUNISON_EVIDENCE_KEY_REVOKED") {
    True -> Revoked
    False -> Active(since, until)
  }
  Ok(RequireKeys([TrustedKey(signer, state)], max_age))
}

fn env_int(key: String, fallback: Int) -> Result(Int, String) {
  case env.get(key) {
    Error(_) -> Ok(fallback)
    Ok(value) if value == "" -> Ok(fallback)
    Ok(value) ->
      int.parse(value)
      |> result.replace_error(
        key <> " must be an integer number of seconds, got: " <> value,
      )
  }
}

fn env_flag(key: String) -> Bool {
  env.flag(key)
}

/// What the policy actually enforces, for a report an operator can read.
pub fn describe(policy: TrustPolicy) -> String {
  case policy {
    FixturesOnly -> "fixtures-only: signatures are not checked"
    RequireKeys(keys, max_age_secs) -> {
      let keys_text = list.map(keys, describe_key) |> string.join("; ")
      let age_text = case max_age_secs {
        0 -> "no attestation age limit"
        _ -> "max attestation age " <> int.to_string(max_age_secs) <> "s"
      }
      keys_text <> "; " <> age_text
    }
  }
}

fn describe_key(key: TrustedKey) -> String {
  let id = key.signer.id
  case key.state {
    Revoked -> id <> ": revoked"
    Active(since, until) ->
      case until == never {
        True -> id <> ": active since " <> int.to_string(since) <> ", no expiry"
        False ->
          id
          <> ": active "
          <> int.to_string(since)
          <> ".."
          <> int.to_string(until)
      }
  }
}
