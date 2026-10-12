import gleam/list
import gleamunison/verify
import simplifile

pub fn native_datalog_test() {
  let base_path = "gleamunison_datalog/"
  let files = [
    "src/01_core.lisp",
    "src/02_index.lisp",
    "src/03_transact.lisp",
    "src/04_schema.lisp",
    "src/05_query.lisp",
    "src/06_aggregate.lisp",
    "src/07_pull.lisp",
    "src/08_temporal.lisp",
    "src/09_rules.lisp",
    "src/10_graph.lisp",
    "src/11_vector.lisp",
    "src/12_bm25.lisp",
    "src/13_actor.lisp",
    "test/test_core.lisp",
    "test/test_query.lisp",
    "test/test_temporal.lisp",
    "test/test_graph.lisp",
  ]

  let combined_content =
    list.fold(files, "", fn(acc, file) {
      let assert Ok(content) = simplifile.read(base_path <> file)
      acc <> "\n" <> content
    })

  // Append execution assertions: count failures across all suites.
  // assert-eq returns (pair 1 name) on pass, (pair 0 "FAIL: name") on fail,
  // so the run is green iff the failure count evaluates to 0.
  let suite_execution =
    "
    (let failures
      (list-filter
        (lam r (eq? (fst r) 0))
        (list-append (run-core-tests 0)
          (list-append (run-query-tests 0)
            (list-append (run-temporal-tests 0)
              (run-graph-tests 0)))))
      (list-length failures))
    "

  let final_content = combined_content <> "\n" <> suite_execution
  let temp_file = "/tmp/datalog_test_combined.lisp"
  let assert Ok(Nil) = simplifile.write(temp_file, final_content)

  let assert Ok(res) = verify.eval_file(temp_file)
  let assert True = res == "0"

  let _ = simplifile.delete(temp_file)
}
