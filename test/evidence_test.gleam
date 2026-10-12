import gleam/bit_array
import gleamunison/evidence.{PropertyCheck, Review, Test}
import gleamunison/identity.{Ref}
import gleamunison/storage
import gleeunit/should

const subject_hex =
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

pub fn attach_then_for_subject_finds_record_test() {
  let adapter = storage.inmemory()
  let assert Ok(#(_, hash)) =
    evidence.attach(
      adapter,
      subject: subject_hex,
      kind: Test,
      verdict: "pass",
      payload: "149 passed, 0 failed",
      ts: 1_760_000_000,
    )
  let found = evidence.for_subject(adapter, subject_hex)
  let assert [record] = found
  record.subject |> should.equal(subject_hex)
  record.kind |> should.equal(Test)
  record.verdict |> should.equal("pass")
  record.payload |> should.equal("149 passed, 0 failed")
  hash |> should.not_equal(subject_hex)
}

pub fn verified_flips_only_with_matching_kind_and_verdict_test() {
  let adapter = storage.inmemory()
  evidence.verified(adapter, subject_hex, Test) |> should.be_false
  let assert Ok(_) =
    evidence.attach(adapter, subject_hex, Review, "approved", "lgtm", 1)
  // Review evidence must not verify Test.
  evidence.verified(adapter, subject_hex, Test) |> should.be_false
  evidence.verified(adapter, subject_hex, Review) |> should.be_true
  let assert Ok(_) =
    evidence.attach(adapter, subject_hex, Test, "fail", "1 failed", 2)
  // A failing verdict is not verification.
  evidence.verified(adapter, subject_hex, Test) |> should.be_false
  let assert Ok(_) =
    evidence.attach(adapter, subject_hex, Test, "pass", "green", 3)
  evidence.verified(adapter, subject_hex, Test) |> should.be_true
}

pub fn tampered_chunk_is_rejected_by_hash_check_test() {
  let adapter = storage.inmemory()
  let assert Ok(#(ref, _)) =
    evidence.attach(adapter, subject_hex, PropertyCheck, "pass", "holds", 1)
  // Attacker rewrites the stored bytes under the same ref.
  let assert Ok(Nil) =
    adapter.insert(ref, bit_array.from_string("evidence:1:forged"))
  evidence.for_subject(adapter, subject_hex) |> should.equal([])
  evidence.verified(adapter, subject_hex, PropertyCheck) |> should.be_false
}

pub fn non_evidence_chunks_are_ignored_test() {
  let adapter = storage.inmemory()
  let junk = identity.hash_bytes(bit_array.from_string("some definition bytes"))
  let assert Ok(Nil) = adapter.insert(Ref(junk), bit_array.from_string("junk"))
  evidence.for_subject(adapter, subject_hex) |> should.equal([])
}
