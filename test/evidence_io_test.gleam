import gleamunison/evidence
import gleamunison/storage
import gleamunison/trust
import gleeunit/should

const subject_hex =
  "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

fn admits(adapter: storage.StorageAdapter, kind: evidence.Kind) -> Bool {
  trust.admits(adapter, subject_hex, kind, trust.FixturesOnly)
}

pub fn io_kind_roundtrips_through_the_store_test() {
  let adapter = storage.inmemory()
  let assert Ok(#(_, _)) =
    evidence.attach(
      adapter,
      subject: subject_hex,
      kind: evidence.Io,
      verdict: "approved",
      payload: "played the game; win and EOF paths both work",
      ts: 1_760_000_000,
    )
  let assert [record] = evidence.for_subject(adapter, subject_hex)
  record.kind |> should.equal(evidence.Io)
  evidence.kind_name(record.kind) |> should.equal("io")
  record.verdict |> should.equal("approved")
}

pub fn io_attestation_verifies_io_but_not_test_test() {
  let adapter = storage.inmemory()
  admits(adapter, evidence.Io) |> should.be_false
  let assert Ok(_) =
    evidence.attach(adapter, subject_hex, evidence.Io, "approved", "ran it", 1)
  admits(adapter, evidence.Io) |> should.be_true
  // Io attestation must never substitute for a test of a pure def.
  admits(adapter, evidence.Test) |> should.be_false
}
