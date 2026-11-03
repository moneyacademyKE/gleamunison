import gleam/option
import gleam/string
import gleamunison/cli_test
import gleamunison/test_runner.{TestResult}
import gleamunison/verify
import gleeunit/should
import simplifile

const empty_path = "/tmp/gleamunison_empty_verify.lisp"

pub fn empty_suite_is_a_failure_test() {
  cli_test.has_failures([]) |> should.be_true
}

pub fn failed_suite_is_a_failure_test() {
  cli_test.has_failures([
    TestResult("test_bad", 0, 1, option.None),
  ])
  |> should.be_true
}

pub fn passing_suite_is_not_a_failure_test() {
  cli_test.has_failures([
    TestResult("test_good", 1, 0, option.None),
  ])
  |> should.be_false
}

pub fn empty_source_is_rejected_test() {
  let assert Ok(Nil) = simplifile.write("", to: empty_path)
  let assert Error(message) = verify.verify_file(empty_path)
  string.contains(message, "source contains no forms") |> should.be_true
}

const malformed_path = "/tmp/gleamunison_malformed_verify.lisp"

/// One pipeline, one parse-error sentence: the eval path and the
/// definition-loading path read the same file through read_terms, so a
/// malformed fixture must produce byte-identical errors from both, with
/// the richer line-and-column rendering.
pub fn parse_error_sentence_is_shared_across_loaders_test() {
  let assert Ok(Nil) =
    simplifile.write("(define broken (lam x\n", to: malformed_path)
  let assert Error(eval_message) = verify.eval_file(malformed_path)
  let assert Error(load_message) = verify.load_defs_file_scoped(malformed_path)
  load_message |> should.equal(eval_message)
  string.contains(eval_message, ", col ") |> should.be_true
}
