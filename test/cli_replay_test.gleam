import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/string
import gleamunison/cli_replay
import gleamunison/effects.{type HandlerFrame, type OpHandler, HandlerFrame}
import gleamunison/repl_eval
import gleamunison/transcript
import gleeunit/should
import simplifile

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn to_dynamic(val: a) -> Dynamic

fn console_frame() -> HandlerFrame {
  HandlerFrame(
    ability: repl_eval.ref_for_name("Console"),
    ops: dict.from_list([#(0, mock_console())]),
  )
}

/// Mock Console.print: returns a marker so replay can prove the recorded
/// result (not a fresh handler call) is what the program observed.
fn mock_console() -> OpHandler {
  fn(_args: List(Dynamic), cont: fn(Dynamic) -> Dynamic) -> Dynamic {
    cont(to_dynamic(42))
  }
}

/// Record a run of a Console-using definition with a mock handler, write
/// the tape, then replay from the file: the replayed result must be
/// identical, and no live handler may run during replay.
pub fn replay_from_tape_file_matches_original_test() {
  let path = "/tmp/cli_replay_test.lisp"
  let assert Ok(_) =
    simplifile.write(
      "(define greet (lam msg (do Console print msg)))\n(define main (greet \"hi\"))",
      to: path,
    )
  let tape_path = "/tmp/cli_replay_test_tape.json"

  // Record: run the def under a wrapped mock handler.
  let rec = transcript.start_with(transcript.CaptureAll)
  let frames = transcript.wrap_frames(rec, [console_frame()])
  let assert Ok(original) = cli_replay.run_definition(path, "main", frames)
  let tape = transcript.capture(rec)
  transcript.stop(rec)
  let json = transcript.to_json(tape)
  let assert Ok(_) = simplifile.write(json, to: tape_path)

  // Replay from the file under playback: no live handler needed.
  let assert Ok(replayed) = cli_replay.replay_from_file(path, "main", tape_path)
  replayed |> should.equal(original)
}

/// A tampered tape must surface as an error, never a silent pass. Record
/// a real v2 tape, flip the ability key in the JSON text: the program's
/// Console call then finds no playback frame and the run must fail loudly.
pub fn replay_with_tampered_ability_key_fails_loudly_test() {
  let path = "/tmp/cli_replay_test2.lisp"
  let assert Ok(_) =
    simplifile.write(
      "(define ask (lam m (do Console print m)))\n(define main (ask \"hey\"))",
      to: path,
    )
  let tape_path = "/tmp/cli_replay_test2_tape.json"

  let rec = transcript.start_with(transcript.CaptureAll)
  let frames = transcript.wrap_frames(rec, [console_frame()])
  let assert Ok(_) = cli_replay.run_definition(path, "main", frames)
  let tape = transcript.capture(rec)
  transcript.stop(rec)
  let assert [entry] = transcript.tape_entries(tape)
  let tampered =
    string.replace(transcript.to_json(tape), entry.ability, "m_deadbeef")
  let assert Ok(_) = simplifile.write(tampered, to: tape_path)

  let result = cli_replay.replay_from_file(path, "main", tape_path)
  should.be_error(result)
}
