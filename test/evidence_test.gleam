import gleam/bit_array
import gleamunison/evidence
import gleamunison/identity.{Ref}
import gleamunison/storage
import gleamunison/trust
import gleeunit/should

const subject_hex =
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

/// Unsigned records are a fixture concern; production always passes a
/// RequireKeys policy.
fn fixtures() -> trust.TrustPolicy {
  trust.FixturesOnly
}

fn admits(adapter: storage.StorageAdapter, kind: evidence.Kind) -> Bool {
  trust.admits(adapter, subject_hex, kind, fixtures())
}

pub fn attach_then_for_subject_finds_record_test() {
  let adapter = storage.inmemory()
  let assert Ok(#(_, hash)) =
    evidence.attach(
      adapter,
      subject: subject_hex,
      kind: evidence.Test,
      verdict: "pass",
      payload: "149 passed, 0 failed",
      ts: 1_760_000_000,
    )
  let assert Ok(snapshot) = evidence.snapshot(adapter)
  let found = evidence.from_snapshot(snapshot, subject_hex)
  let assert [record] = found
  record.subject |> should.equal(subject_hex)
  record.kind |> should.equal(evidence.Test)
  record.verdict |> should.equal("pass")
  record.payload |> should.equal("149 passed, 0 failed")
  hash |> should.not_equal(subject_hex)
}

pub fn verified_flips_only_with_matching_kind_and_verdict_test() {
  let adapter = storage.inmemory()
  admits(adapter, evidence.Test) |> should.be_false
  let assert Ok(_) =
    evidence.attach(
      adapter,
      subject_hex,
      evidence.Review,
      "approved",
      "lgtm",
      1,
    )
  // Review evidence must not verify Test.
  admits(adapter, evidence.Test) |> should.be_false
  admits(adapter, evidence.Review) |> should.be_true
  let assert Ok(_) =
    evidence.attach(adapter, subject_hex, evidence.Test, "fail", "1 failed", 2)
  // A failing verdict is not verification.
  admits(adapter, evidence.Test) |> should.be_false
  let assert Ok(_) =
    evidence.attach(adapter, subject_hex, evidence.Test, "pass", "green", 3)
  admits(adapter, evidence.Test) |> should.be_true
}

pub fn tampered_chunk_is_rejected_by_hash_check_test() {
  let adapter = storage.inmemory()
  let assert Ok(#(ref, _)) =
    evidence.attach(
      adapter,
      subject_hex,
      evidence.PropertyCheck,
      "pass",
      "holds",
      1,
    )
  // Attacker rewrites the stored bytes under the same ref.
  let assert Ok(Nil) =
    adapter.insert(ref, bit_array.from_string("evidence:1:forged"))
  let assert Ok(snapshot) = evidence.snapshot(adapter)
  evidence.from_snapshot(snapshot, subject_hex) |> should.equal([])
  admits(adapter, evidence.PropertyCheck) |> should.be_false
}

pub fn non_evidence_chunks_are_ignored_test() {
  let adapter = storage.inmemory()
  let junk = identity.hash_bytes(bit_array.from_string("some definition bytes"))
  let assert Ok(Nil) = adapter.insert(Ref(junk), bit_array.from_string("junk"))
  let assert Ok(snapshot) = evidence.snapshot(adapter)
  evidence.from_snapshot(snapshot, subject_hex) |> should.equal([])
}

pub fn unsigned_evidence_is_rejected_by_require_keys_policy_test() {
  let adapter = storage.inmemory()
  let trusted = evidence.signer("ci", <<"ci-secret">>)
  let assert Ok(_) =
    evidence.attach(adapter, subject_hex, evidence.Test, "pass", "legacy", 1)
  trust.verified(
    adapter,
    subject_hex,
    evidence.Test,
    trust.policy([trust.active(trusted, 0, trust.never)]),
  )
  |> should.equal(Error(trust.UnsignedRecord))
}

pub fn signed_evidence_requires_matching_identity_and_secret_test() {
  let adapter = storage.inmemory()
  let trusted = evidence.signer("ci", <<"ci-secret">>)
  let wrong_secret = evidence.signer("ci", <<"wrong-secret">>)
  let assert Ok(_) =
    evidence.attach_signed(
      adapter,
      signer: trusted,
      subject: subject_hex,
      kind: evidence.Test,
      verdict: "pass",
      payload: "signed by ci",
      ts: 2,
    )
  trust.verified(
    adapter,
    subject_hex,
    evidence.Test,
    trust.policy([trust.active(trusted, 0, trust.never)]),
  )
  |> should.equal(Ok(Nil))
  trust.verified(
    adapter,
    subject_hex,
    evidence.Test,
    trust.policy([trust.active(wrong_secret, 0, trust.never)]),
  )
  |> should.equal(Error(trust.SignatureMismatch("ci")))
}
