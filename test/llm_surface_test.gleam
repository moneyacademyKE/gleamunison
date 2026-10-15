//// The LLM ability as surface syntax: `(do LLM complete "prompt")` must
//// elaborate (LLM is a bootstrap ability) and dispatch to whichever handler
//// frame is installed — mock in tests, live provider by default.

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleamunison/cli_replay
import gleamunison/effects.{type HandlerFrame, type OpHandler, HandlerFrame}
import gleamunison/llm
import gleamunison/repl_eval
import gleeunit/should
import simplifile

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn to_dynamic(val: a) -> Dynamic

/// The ability ref surface code resolves must be the name hash — the same
/// key handler frames are installed under.
pub fn ability_ref_is_name_hash_test() {
  llm.ability_ref()
  |> should.equal(repl_eval.ref_for_name("LLM"))
}

/// Mock LLM.complete: the program's prompt comes back prefixed, so the test
/// proves the op actually dispatched through the frame (not a default).
fn mock_llm() -> OpHandler {
  fn(args: List(Dynamic), cont: fn(Dynamic) -> Dynamic) -> Dynamic {
    case args {
      [prompt, ..] -> {
        let p: String = unsafe_coerce(prompt)
        cont(to_dynamic("mocked:" <> p))
      }
      [] -> cont(to_dynamic("mocked:"))
    }
  }
}

@external(erlang, "gleamunison_ffi", "from_dynamic")
fn unsafe_coerce(val: Dynamic) -> a

fn llm_frame() -> HandlerFrame {
  HandlerFrame(
    ability: llm.ability_ref(),
    ops: dict.from_list([#(0, mock_llm())]),
  )
}

/// End to end: surface `(do LLM complete ...)` elaborates against the
/// bootstrap ability and dispatches to the installed mock frame.
pub fn surface_llm_complete_dispatches_to_frame_test() {
  let path = "/tmp/llm_surface_test.lisp"
  let assert Ok(_) =
    simplifile.write(
      "(define ask (lam m (do LLM complete m)))\n(define main (ask \"hi\"))",
      to: path,
    )
  let result = cli_replay.run_definition(path, "main", [llm_frame()])
  // eval renders strings as Erlang binaries.
  result |> should.equal(Ok("<<\"mocked:hi\">>"))
}
