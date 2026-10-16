import gleamunison/cli_replay
import gleeunit/should
import simplifile

/// Dogfood loop 8: the model's game crashed on EOF because `string->int`
/// raises `badarg` on non-numeric input. A builtin that parses user input
/// must return a value, not kill the process. `left` is success, `right`
/// is the error — the same constructors the surface already matches on.
pub fn string_to_int_returns_left_on_success_test() {
  let path = "/tmp/string_to_int_ok.lisp"
  let assert Ok(_) =
    simplifile.write(
      "(define main (string->int \"42\"))",
      to: path,
    )
  let assert Ok(result) = cli_replay.run_definition(path, "main", [])
  result |> should.equal("{m_f2541480,42}")
}

pub fn string_to_int_returns_right_on_garbage_test() {
  let path = "/tmp/string_to_int_bad.lisp"
  let assert Ok(_) =
    simplifile.write(
      "(define main (string->int \"nope\"))",
      to: path,
    )
  let assert Ok(result) = cli_replay.run_definition(path, "main", [])
  result |> should.equal("{m_8563bad9,bad_integer}")
}

/// The exact dogfood crash: EOF gives `read_line` an empty string.
pub fn string_to_int_returns_right_on_empty_test() {
  let path = "/tmp/string_to_int_empty.lisp"
  let assert Ok(_) =
    simplifile.write(
      "(define main (string->int \"\"))",
      to: path,
    )
  let assert Ok(result) = cli_replay.run_definition(path, "main", [])
  result |> should.equal("{m_8563bad9,bad_integer}")
}
