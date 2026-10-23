import gleam/bit_array
import gleamunison/evidence.{Test}
import gleamunison/storage
import gleamunison/trust
import gleeunit/should

const subject =
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

fn key_a() -> evidence.Signer {
  evidence.signer("key-a", bit_array.from_string("secret-a"))
}

fn key_b() -> evidence.Signer {
  evidence.signer("key-b", bit_array.from_string("secret-b"))
}

fn record(signer: evidence.Signer, ts: Int) -> evidence.Evidence {
  evidence.sign(signer, subject, Test, "pass", "green", ts)
}

pub fn unknown_signer_is_refused_test() {
  let policy = trust.policy([trust.active(key_a(), 0, 1000)])
  let record = record(key_b(), 500)
  let assert Error(refusal) = trust.admit(policy, record)
  trust.refusal_name(refusal) |> should.equal("unknown_signer:key-b")
}

pub fn revoked_key_is_refused_test() {
  let policy = trust.policy([trust.revoked(key_a())])
  let record = record(key_a(), 500)
  let assert Error(refusal) = trust.admit(policy, record)
  trust.refusal_name(refusal) |> should.equal("key_revoked:key-a")
}

pub fn expired_key_is_refused_test() {
  let policy = trust.policy([trust.active(key_a(), 0, 1000)])
  let record = record(key_a(), 1500)
  let assert Error(refusal) = trust.admit(policy, record)
  trust.refusal_name(refusal) |> should.equal("key_expired:key-a")
}

pub fn not_yet_valid_key_is_refused_test() {
  let policy = trust.policy([trust.active(key_a(), 500, 1000)])
  let record = record(key_a(), 100)
  let assert Error(refusal) = trust.admit(policy, record)
  trust.refusal_name(refusal) |> should.equal("key_not_yet_valid:key-a")
}

pub fn active_key_within_window_is_admitted_test() {
  let policy = trust.policy([trust.active(key_a(), 0, 1000)])
  let record = record(key_a(), 500)
  trust.admit(policy, record) |> should.equal(Ok(record))
}

pub fn rotation_overlap_admits_both_keys_test() {
  // Old key valid until 1000, new key valid from 800: overlap [800, 1000).
  let policy =
    trust.policy([
      trust.active(key_a(), 0, 1000),
      trust.active(key_b(), 800, 2000),
    ])
  let old_record = record(key_a(), 900)
  let new_record = record(key_b(), 900)
  trust.admit(policy, old_record) |> should.equal(Ok(old_record))
  trust.admit(policy, new_record) |> should.equal(Ok(new_record))
  // After rotation completes, the old key refuses.
  let late_old = record(key_a(), 1500)
  trust.admit(policy, late_old) |> should.be_error
}

pub fn tampered_payload_breaks_signature_test() {
  let policy = trust.policy([trust.active(key_a(), 0, 1000)])
  let signed = record(key_a(), 500)
  let forged =
    evidence.Evidence(
      subject: signed.subject,
      kind: signed.kind,
      verdict: "fail",
      payload: "forged",
      ts: signed.ts,
      signer: signed.signer,
      signature: signed.signature,
    )
  let assert Error(refusal) = trust.admit(policy, forged)
  trust.refusal_name(refusal) |> should.equal("signature_mismatch:key-a")
}

pub fn unsigned_record_is_refused_in_production_policy_test() {
  let policy = trust.policy([trust.active(key_a(), 0, 1000)])
  let unsigned =
    evidence.Evidence(
      subject: subject,
      kind: Test,
      verdict: "pass",
      payload: "green",
      ts: 500,
      signer: "",
      signature: "",
    )
  let assert Error(refusal) = trust.admit(policy, unsigned)
  trust.refusal_name(refusal) |> should.equal("unsigned_record")
}

// --- policy enforcement against a store -------------------------------------

/// An expired key is a refusal with a name, not a bare false: an operator
/// reading "key_expired" rotates the key, one reading "no_record" runs tests.
pub fn verified_names_key_expiry_test() {
  let adapter = storage.inmemory()
  let assert Ok(_) =
    evidence.attach_signed(
      adapter,
      key_a(),
      subject,
      Test,
      "pass",
      "green",
      1500,
    )
  trust.verified(
    adapter,
    subject,
    Test,
    trust.policy([trust.active(key_a(), 0, 1000)]),
  )
  |> should.equal(Error(trust.KeyExpired("key-a", 1000)))
}

pub fn verified_names_revocation_test() {
  let adapter = storage.inmemory()
  let assert Ok(_) =
    evidence.attach_signed(
      adapter,
      key_a(),
      subject,
      Test,
      "pass",
      "green",
      500,
    )
  trust.verified(adapter, subject, Test, trust.policy([trust.revoked(key_a())]))
  |> should.equal(Error(trust.KeyRevoked("key-a")))
}

pub fn verified_admits_within_the_window_test() {
  let adapter = storage.inmemory()
  let assert Ok(_) =
    evidence.attach_signed(
      adapter,
      key_a(),
      subject,
      Test,
      "pass",
      "green",
      500,
    )
  trust.verified(
    adapter,
    subject,
    Test,
    trust.policy([trust.active(key_a(), 0, 1000)]),
  )
  |> should.equal(Ok(Nil))
}

/// Rotation overlap: the newest record is signed by the retiring key, whose
/// window has closed, but an older record from the incoming key still admits.
pub fn rotation_overlap_admits_the_older_record_test() {
  let adapter = storage.inmemory()
  let assert Ok(_) =
    evidence.attach_signed(adapter, key_a(), subject, Test, "pass", "old", 900)
  let assert Ok(_) =
    evidence.attach_signed(adapter, key_b(), subject, Test, "pass", "new", 850)
  let policy =
    trust.policy([
      trust.active(key_a(), 0, 880),
      trust.active(key_b(), 800, 2000),
    ])
  // key-a's 900 record is outside its window; key-b's 850 record is inside.
  trust.verified_at(adapter, subject, Test, policy, 1000)
  |> should.equal(Ok(Nil))
}

/// A stale attestation is refused even with a valid key: "tested once in 2019"
/// is not evidence that today's binary works.
pub fn stale_attestation_is_refused_test() {
  let adapter = storage.inmemory()
  let assert Ok(_) =
    evidence.attach_signed(
      adapter,
      key_a(),
      subject,
      Test,
      "pass",
      "green",
      100,
    )
  let policy = trust.RequireKeys([trust.active(key_a(), 0, trust.never)], 1000)
  trust.verified_at(adapter, subject, Test, policy, 5000)
  |> should.equal(Error(trust.AttestationTooOld("test", 100, 1000)))
}

pub fn fresh_attestation_passes_the_age_limit_test() {
  let adapter = storage.inmemory()
  let assert Ok(_) =
    evidence.attach_signed(
      adapter,
      key_a(),
      subject,
      Test,
      "pass",
      "green",
      100,
    )
  let policy = trust.RequireKeys([trust.active(key_a(), 0, trust.never)], 1000)
  trust.verified_at(adapter, subject, Test, policy, 900)
  |> should.equal(Ok(Nil))
}

/// A failing verdict is reported as such, never as "no evidence".
pub fn failing_verdict_is_named_test() {
  let adapter = storage.inmemory()
  let assert Ok(_) =
    evidence.attach_signed(
      adapter,
      key_a(),
      subject,
      Test,
      "fail",
      "1 failed",
      5,
    )
  trust.verified(
    adapter,
    subject,
    Test,
    trust.policy([trust.active(key_a(), 0, trust.never)]),
  )
  |> should.equal(Error(trust.NoPassingVerdict("test", "fail")))
}

pub fn describe_states_what_is_enforced_test() {
  trust.describe(trust.policy([trust.active(key_a(), 0, trust.never)]))
  |> should.equal("key-a: active since 0, no expiry; no attestation age limit")
  trust.describe(trust.policy([trust.revoked(key_a())]))
  |> should.equal("key-a: revoked; no attestation age limit")
}
