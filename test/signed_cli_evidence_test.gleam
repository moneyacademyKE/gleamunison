import gleam/bit_array
import gleam/string
import gleamunison/cli_evidence
import gleamunison/evidence
import gleamunison/storage
import gleeunit/should

pub fn signed_report_uses_explicit_trust_policy_test() {
  let adapter = storage.inmemory()
  let signer =
    evidence.signer("test-only", bit_array.from_string("local-fixture"))
  let stranger =
    evidence.signer("stranger", bit_array.from_string("other-fixture"))
  let subject = string.repeat("a", 64)
  let assert Ok(_) =
    evidence.attach_signed(
      adapter,
      signer,
      subject,
      evidence.Test,
      "pass",
      "regression",
      1,
    )
  cli_evidence.report_with_policy(
    adapter,
    subject,
    evidence.require_signer(signer),
  )
  |> string.contains("verified: test evidence with passing verdict exists")
  |> should.be_true
  cli_evidence.report_with_policy(
    adapter,
    subject,
    evidence.require_signer(stranger),
  )
  |> string.contains("verified: no passing test attestation")
  |> should.be_true
  cli_evidence.report(adapter, subject)
  |> string.contains("verified: no passing test attestation")
  |> should.be_true
}
