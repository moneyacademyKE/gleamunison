import gleam/bit_array
import gleam/string
import gleamunison/cli_evidence
import gleamunison/evidence
import gleamunison/storage
import gleamunison/trust
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
    trust.policy([trust.active(signer, 0, trust.never)]),
  )
  |> string.contains("test: admitted by the policy")
  |> should.be_true
  cli_evidence.report_with_policy(
    adapter,
    subject,
    trust.policy([trust.active(stranger, 0, trust.never)]),
  )
  |> string.contains("test: refused (")
  |> should.be_true
  // The fixtures helper is unsigned by construction, and it says so in the
  // policy line rather than implying a signature was checked.
  let fixture_report = cli_evidence.report(adapter, subject)
  fixture_report
  |> string.contains("policy: fixtures-only: signatures are not checked")
  |> should.be_true
  fixture_report
  |> string.contains("test: admitted by the policy")
  |> should.be_true
}
