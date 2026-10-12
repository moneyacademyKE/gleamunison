import gleam/list
import gleam/string
import gleamunison/codebase
import gleamunison/elab_types.{type SurfaceTerm, SApply, SDo, SInt, SVar, SurfaceTermDef}
import gleamunison/evidence
import gleamunison/identity.{hash_to_debug_string}
import gleamunison/repl_eval
import gleamunison/storage
import gleamunison/test_runner
import gleamunison/types.{empty_cache}
import gleamunison/verify
import gleeunit/should

fn boot() {
  repl_eval.bootstrap_defs(verify.get_init_defs(), empty_cache())
}

fn expect_one() -> SurfaceTerm {
  SDo("Test", "expect", [SInt(1)])
}

pub fn passing_test_records_one_pass_test() {
  let #(cache, defs) = boot()
  let user_defs = [#("test_trivial", SurfaceTermDef(expect_one()))]
  let results = test_runner.run_suite(list.append(defs, user_defs), cache)
  let assert [result] = results
  result.name |> should.equal("test_trivial")
  result.passed |> should.equal(1)
  result.failed |> should.equal(0)
}

pub fn failing_test_records_one_failure_test() {
  let #(cache, defs) = boot()
  let user_defs = [#("test_bad", SurfaceTermDef(SDo("Test", "expect", [SInt(0)])))]
  let results = test_runner.run_suite(list.append(defs, user_defs), cache)
  let assert [result] = results
  result.passed |> should.equal(0)
  result.failed |> should.equal(1)
}

pub fn expects_using_defs_pass_test() {
  let #(cache, defs) = boot()
  let user_defs = [
    #("answer", SurfaceTermDef(SInt(42))),
    #(
      "test_answer",
      SurfaceTermDef(
        SDo("Test", "expect", [
          SApply(
            SApply(SVar("eq?"), SVar("answer")),
            SInt(42),
          ),
        ]),
      ),
    ),
  ]
  let results = test_runner.run_suite(list.append(defs, user_defs), cache)
  let assert [result] = results
  result.name |> should.equal("test_answer")
  result.passed |> should.equal(1)
}

pub fn results_attach_evidence_to_subject_test() {
  let #(cache, defs) = boot()
  let user_defs = [
    #("answer", SurfaceTermDef(SInt(42))),
    #(
      "test_answer",
      SurfaceTermDef(
        SDo("Test", "expect", [
          SApply(SApply(SVar("eq?"), SVar("answer")), SInt(42)),
        ]),
      ),
    ),
  ]
  let all_defs = list.append(defs, user_defs)
  let results = test_runner.run_suite(all_defs, cache)
  let store = storage.inmemory()
  let attached = test_runner.attach_results(store, results, all_defs, cache)
  list.length(attached) |> should.equal(1)
  // Evidence must be retrievable by the SUBJECT definition's hash.
  let assert Ok(subject_def) =
    test_runner.elaborated_def_for("answer", all_defs, cache)
  let subject_hex =
    hash_to_debug_string(codebase.hash_of_definition(subject_def))
  let found = evidence.for_subject(store, subject_hex)
  list.length(found) |> should.equal(1)
  let assert [ev] = found
  ev.kind |> should.equal(evidence.Test)
  ev.verdict |> should.equal("pass")
  string.contains(ev.payload, "test_answer") |> should.be_true
}

pub fn untested_tests_attach_nothing_test() {
  let #(cache, defs) = boot()
  let user_defs = [#("test_orphan", SurfaceTermDef(expect_one()))]
  let all_defs = list.append(defs, user_defs)
  let results = test_runner.run_suite(all_defs, cache)
  let store = storage.inmemory()
  let attached = test_runner.attach_results(store, results, all_defs, cache)
  list.length(attached) |> should.equal(0)
}
