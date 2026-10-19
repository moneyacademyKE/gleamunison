//// `gleamunison replay <file.lisp> <def> <tape.json>` — re-run a definition
//// against a recorded transcript. Playback serves recorded op results; the
//// real handlers never run. Divergence (wrong ability, wrong op, exhausted
//// tape) fails loudly. Verification, not vibes: a clean replay proves the
//// run the tape records is the run the code performs.

import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/result
import gleam/string
import gleamunison/cli_result
import gleamunison/compile
import gleamunison/effects.{type HandlerFrame, RuntimeConfig}

import gleamunison/repl_eval
import gleamunison/transcript
import gleamunison/verify
import simplifile

@external(erlang, "gleamunison_ffi", "rescue")
fn ffi_rescue(f: fn() -> a) -> Result(a, String)

@external(erlang, "gleamunison_ffi", "from_dynamic")
fn from_dynamic(val: Dynamic) -> a

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn to_dynamic(val: a) -> Dynamic

/// Bare module evaluation: no default ability handlers, so caller-installed
/// frames (recording wraps, playback, capability gates) are the whole stack.
@external(erlang, "gleamunison_repl_ffi", "eval_module_bare")
fn eval_module_bare(mod_name: String) -> Result(String, String)

pub fn command(args: List(String)) -> Result(Nil, String) {
  case args {
    [path, name, tape_path] ->
      case replay_from_file(path, name, tape_path) {
        Ok(val) ->
          cli_result.success("replay verified: " <> name <> " = " <> val)
        Error(err) -> Error("replay failed: " <> err)
      }
    _ -> Error("usage: gleam run -- replay <file.lisp> <def-name> <tape.json>")
  }
}

/// Run a definition under caller-supplied handler frames (the recording
/// path: wrap them with transcript.wrap_frames first).
pub fn run_definition(
  path: String,
  name: String,
  frames: List(HandlerFrame),
) -> Result(String, String) {
  use mod_name <- result.try(load_and_compile(path, name))
  let result: Result(String, String) =
    from_dynamic(
      effects.run(RuntimeConfig(ambient_handlers: frames), fn() {
        to_dynamic(eval_module_bare(mod_name))
      }),
    )
  result
}

/// Replay a definition against a tape file. The tape must carry raw values
/// (v2 format); an audit-only tape cannot drive a replay.
pub fn replay_from_file(
  path: String,
  name: String,
  tape_path: String,
) -> Result(String, String) {
  use tape_text <- result.try(case simplifile.read(tape_path) {
    Ok(t) -> Ok(t)
    Error(e) -> Error("replay: cannot read tape: " <> string.inspect(e))
  })
  use tape <- result.try(transcript.from_json(tape_text))
  case transcript.is_replayable(tape) {
    False -> Error("replay: tape is audit-only (no raw values recorded)")
    True -> {
      use mod_name <- result.try(load_and_compile(path, name))
      case
        ffi_rescue(fn() {
          transcript.run_with_playback(tape, fn() { eval_module_bare(mod_name) })
        })
      {
        Error(reason) -> Error("replay diverged from tape: " <> reason)
        Ok(Error(err)) -> Error("replay runtime error: " <> err)
        Ok(Ok(val)) -> Ok(val)
      }
    }
  }
}

/// Load a file and compile the named definition. Only `define` forms are
/// processed: evaluating a stray expression at load time would call real
/// handlers outside any replay/recording frame, which is exactly the
/// accident this tool exists to prevent. The loader itself lives in
/// verify.load_defs_file — one loader, shared by every CLI that loads code.
fn load_and_compile(path: String, name: String) -> Result(String, String) {
  use #(_cache, defs) <- result.try(verify.load_defs_file(path))
  case list.any(defs, fn(pair) { pair.0 == name }) {
    False -> Error("replay: no definition named " <> name <> " in " <> path)
    True -> Ok(compile.module_name_for(repl_eval.ref_for_name(name)))
  }
}
