import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/option
import gleam/string
import gleamunison/cli_replay
import gleamunison/cli_tape_to_test
import gleamunison/cli_test
import gleamunison/effects.{type HandlerFrame, type OpHandler, HandlerFrame}
import gleamunison/repl_eval
import gleamunison/storage
import gleamunison/test_runner
import gleamunison/transcript
import gleeunit/should
import simplifile

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn to_dynamic(val: a) -> Dynamic

fn mock_console() -> OpHandler {
  fn(_args: List(Dynamic), cont: fn(Dynamic) -> Dynamic) -> Dynamic {
    cont(to_dynamic(42))
  }
}

fn console_frame() -> HandlerFrame {
  HandlerFrame(
    ability: repl_eval.ref_for_name("Console"),
    ops: dict.from_list([#(0, mock_console())]),
  )
}

fn subject_path() -> String {
  "/tmp/tape_to_test_subject.lisp"
}

fn write_subject() -> Nil {
  let assert Ok(_) =
    simplifile.write(
      "(define greet (lam msg (do Console print msg)))\n(define main (greet \"hi\"))",
      to: subject_path(),
    )
  Nil
}

fn record_tape() -> String {
  write_subject()
  let rec = transcript.start()
  let frames = transcript.wrap_frames(rec, [console_frame()])
  let assert Ok(_) = cli_replay.run_definition(subject_path(), "main", frames)
  let tape = transcript.capture(rec)
  transcript.stop(rec)
  transcript.to_json(tape)
}

/// The generated file must contain the mock handler (pinning the recorded
/// args + result) and a test_ def asserting the recorded final value.
pub fn generate_contains_mock_and_test_test() {
  let json = record_tape()
  let assert Ok(source) =
    cli_tape_to_test.generate(subject_path(), "main", json)
  string.contains(source, "tape_mock") |> should.be_true
  string.contains(source, "test_main_tape") |> should.be_true
  string.contains(source, "(cont 42)") |> should.be_true
  string.contains(source, "(eq?") |> should.be_true
}

/// The golden rule: the generated test file parses, elaborates, and the
/// suite passes under cli_test. A regression test that doesn't run is a
/// drawing, not a test.
pub fn generated_test_suite_passes_test() {
  let json = record_tape()
  let assert Ok(source) =
    cli_tape_to_test.generate(subject_path(), "main", json)
  let gen_path = "/tmp/tape_to_test_generated.lisp"
  let assert Ok(_) = simplifile.write(source, to: gen_path)
  let adapter = storage.inmemory()
  let assert Ok(#(results, _attachments)) = cli_test.run_file(gen_path, adapter)
  let assert [_, ..] = results
  list_all_pass(results) |> should.be_true
}

fn list_all_pass(results: List(test_runner.TestResult)) -> Bool {
  case results {
    [] -> True
    [r, ..rest] ->
      case r.failed == 0 && r.error == option.None {
        True -> list_all_pass(rest)
        False -> False
      }
  }
}
