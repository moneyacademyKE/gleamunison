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
