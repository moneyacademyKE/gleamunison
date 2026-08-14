import gleam/list
import gleam/string
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

  // Append execution assertions
  let suite_execution =
    "
    (let _ (run-core-tests 0)
      (let _ (run-query-tests 0)
        (let _ (run-temporal-tests 0)
          (let _ (run-graph-tests 0)
            \"ALL NATIVE DATALOG TESTS PASSED!\"))))
    "

  let final_content = combined_content <> "\n" <> suite_execution
  let temp_file = "/tmp/datalog_test_combined.lisp"
  let assert Ok(Nil) = simplifile.write(temp_file, final_content)

  let assert Ok(res) = verify.verify_file(temp_file)
  let assert True = string.contains(res, "Verification successful")

  let _ = simplifile.delete(temp_file)
}
