import gleam/list
import gleam/string
import gleamunison/cli_datalog
import gleeunit/should
import simplifile

/// End-to-end: engine loads, datoms transact, a two-clause join runs,
/// and the result value is printed. The join is the regression case —
/// it needed dict-keys iteration (was silently returning empty before).
pub fn datalog_join_query_end_to_end_test() {
  let script =
    "
(define db
  (let db (db-assert db-empty 1 \"name\" \"Alice\")
    (let db (db-assert db 1 \"age\" 30)
      (let db (db-assert db 2 \"name\" \"Bob\")
        (db-assert db 2 \"age\" 25)))))
(define q
  (list
    (pair (q-var \"?e\") (pair \"name\" (q-var \"?name\")))
    (pair (q-var \"?e\") (pair \"age\" (q-val 30)))))
(list-length (db-query db q))
"
  let path = "/tmp/cli_datalog_test.lisp"
  let assert Ok(Nil) = simplifile.write(path, script)
  let assert Ok(out) = cli_datalog.run(path)
  // The final form's value is the last line of output.
  let lines = string.split(out, "\n")
  let assert Ok(last) = list.last(lines)
  last |> should.equal("1")
  let _ = simplifile.delete(path)
}

pub fn datalog_reports_missing_script_test() {
  let assert Error(err) = cli_datalog.run("/nonexistent/script.lisp")
  string.contains(err, "cannot read script") |> should.be_true
}
