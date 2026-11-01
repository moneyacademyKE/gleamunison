//// Test-only recording-side eval harness (bk-f850): run a definition from
//// file under caller-supplied handler frames. Production replay goes through
//// cli_replay.command → replay_from_file → transcript.run_with_playback;
//// the fine-grained recording entry that used to live in src had zero
//// production callers, so the harness lives here and shares the one
//// name→module authority (cli_replay.load_and_compile).

import gleam/result
import gleamunison/cli_replay
import gleamunison/dynamic_ffi.{from_dynamic, to_dynamic}
import gleamunison/effects.{type HandlerFrame, RuntimeConfig}

@external(erlang, "gleamunison_repl_ffi", "eval_module_bare")
fn eval_module_bare(mod_name: String) -> Result(String, String)

/// Run a definition under caller-supplied handler frames (the recording
/// path: wrap them with transcript.wrap_frames first).
pub fn run_definition(
  path: String,
  name: String,
  frames: List(HandlerFrame),
) -> Result(String, String) {
  use mod_name <- result.try(cli_replay.load_and_compile(path, name))
  let result: Result(String, String) =
    from_dynamic(
      effects.run(RuntimeConfig(ambient_handlers: frames), fn() {
        to_dynamic(eval_module_bare(mod_name))
      }),
    )
  result
}
