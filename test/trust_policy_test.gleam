import gleam/bit_array
import gleamunison/evidence.{Test}
import gleamunison/trust
import gleeunit/should

const subject = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

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
