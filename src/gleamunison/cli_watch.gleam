//// `gleamunison watch <file.lisp>` — re-verify on every save.
////
//// Unison's `run>` watch expressions, adapted to our scratch-file workflow:
//// poll the file's mtime, and when it moves, re-run the verify pipeline and
//// print the result. The decision (poll) is separate from the action (verify)
//// so the decision is unit-testable with real files.

import gleam/io
import gleamunison/verify
import simplifile

// Erlang returns the atom `ok`; the value is discarded.
@external(erlang, "timer", "sleep")
fn sleep(ms: Int) -> Nil

pub type Poll {
  Changed(mtime: Int)
  Unchanged
  Missing
}

/// One watch decision: has the file changed since `last_mtime`?
pub fn poll(path: String, last_mtime: Int) -> Poll {
  case simplifile.file_info(path) {
    Error(_) -> Missing
    Ok(info) ->
      case info.mtime_seconds > last_mtime {
        True -> Changed(info.mtime_seconds)
        False -> Unchanged
      }
  }
}

/// Watch loop: verify once, then re-verify on every mtime bump, forever.
pub fn command(path: String) -> Nil {
  io.println("watching " <> path <> " — Ctrl-C to stop")
  run_and_report(path)
  loop(path, mtime_or_zero(path))
}

fn loop(path: String, last_mtime: Int) -> Nil {
  sleep(500)
  case poll(path, last_mtime) {
    Changed(mtime) -> {
      run_and_report(path)
      loop(path, mtime)
    }
    Unchanged -> loop(path, last_mtime)
    Missing -> {
      io.println("watch: " <> path <> " was deleted — still watching")
      loop(path, last_mtime)
    }
  }
}

fn run_and_report(path: String) -> Nil {
  case verify.verify_file(path) {
    Ok(msg) -> io.println("✓ " <> msg)
    Error(err) -> io.println("✗ " <> err)
  }
}

fn mtime_or_zero(path: String) -> Int {
  case simplifile.file_info(path) {
    Ok(info) -> info.mtime_seconds
    Error(_) -> 0
  }
}

/// Help text fragment for the CLI banner.
pub fn usage() -> String {
  "  watch <file.lisp> — re-verify the file on every save"
}
