import gleam/list
import gleam/string
import gleamunison/cli_evidence
import gleamunison/cli_test
import gleamunison/evidence
import gleamunison/storage
import gleeunit/should
import simplifile

const suite_path = "/tmp/cli_test_suite.lisp"

fn write_suite() {
  let assert Ok(_) =
    simplifile.write(
      "(define double (lam n (mul n 2)))\n(define test_double (do Test expect (eq? (double 21) 42)))",
      to: suite_path,
    )
  Nil
}

/// The loop, closed: run a suite, get results, and evidence lands on the
/// subject's hash — readable back through the same adapter.
pub fn test_runs_suite_and_attaches_evidence_test() {
  write_suite()
  let adapter = storage.inmemory()
  let assert Ok(#(results, attachments)) =
    cli_test.run_file(suite_path, adapter)
  let assert [result] = results
  result.name |> should.equal("test_double")
  result.failed |> should.equal(0)
  let assert [#(subject_hex, payload)] = attachments
  string.contains(payload, "1 passed") |> should.be_true
  // The attestation is on the store, keyed to the subject's content hash.
  let stored = evidence.for_subject(adapter, subject_hex)
  list.length(stored) |> should.equal(1)
  evidence.verified(adapter, subject_hex, evidence.Test) |> should.be_true
}

/// evidence CLI renders attestations for a hash, integrity-checked.
pub fn evidence_lists_attestations_test() {
  write_suite()
  let adapter = storage.inmemory()
  let assert Ok(#(_results, attachments)) =
    cli_test.run_file(suite_path, adapter)
  let assert [#(subject_hex, _)] = attachments
  let report = cli_evidence.report(adapter, subject_hex)
  string.contains(report, "test") |> should.be_true
  string.contains(report, "pass") |> should.be_true
}

/// A hash with no attestations says so plainly.
pub fn evidence_reports_absence_test() {
  let adapter = storage.inmemory()
  let report = cli_evidence.report(adapter, "deadbeef")
  string.contains(report, "no evidence") |> should.be_true
}

pub fn failed_evidence_write_is_not_a_successful_run_test() {
  write_suite()
  let adapter = storage.inmemory()
  let broken =
    storage.StorageAdapter(..adapter, insert: fn(_, _) {
      Error(storage.StorageError("write refused"))
    })
  let assert Error(message) = cli_test.run_file(suite_path, broken)
  string.contains(message, "cannot attach evidence") |> should.be_true
}
