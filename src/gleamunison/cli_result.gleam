//// One process-exit boundary for command results. Domain code returns data;
//// only the CLI decides whether the process has succeeded.

import gleam/io

@external(erlang, "gleamunison_ffi", "halt_failure")
fn halt_failure() -> Nil

pub fn finish(result: Result(Nil, String)) -> Nil {
  case result {
    Ok(Nil) -> Nil
    Error(message) -> fail(message)
  }
}

pub fn fail(message: String) -> Nil {
  io.println(message)
  halt_failure()
}
