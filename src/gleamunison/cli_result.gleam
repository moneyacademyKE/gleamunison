//// One process-exit boundary for command results. Domain code returns data;
//// only the CLI decides whether the process has succeeded.
////
//// Exit codes are a contract a script reads: 0 success, 1 refused (the
//// command understood the request and declined it), 2 could-not-resolve (the
//// request named something absent). Errors go to stderr so stdout carries
//// only the result.

import gleam/io

@external(erlang, "gleamunison_ffi", "halt_failure")
fn halt_failure() -> Nil

@external(erlang, "gleamunison_ffi", "halt_failure_code")
fn halt_failure_code(code: Int) -> Nil

pub const refused = 1

pub const unresolvable = 2

pub fn finish(result: Result(Nil, String)) -> Nil {
  case result {
    Ok(Nil) -> Nil
    Error(message) -> fail(message)
  }
}

pub fn success(message: String) -> Result(Nil, String) {
  io.println(message)
  Ok(Nil)
}

pub fn print(result: Result(String, String)) -> Nil {
  case result {
    Ok(message) -> finish(success(message))
    Error(message) -> fail(message)
  }
}

pub fn fail(message: String) -> Nil {
  io.println(message)
  halt_failure()
}

/// Fail with an explicit exit code, on stderr. Used where the code carries
/// meaning: a caller can tell "refused" from "no such definition".
pub fn fail_with_code(code: Int, message: String) -> Nil {
  io.println_error(message)
  halt_failure_code(code)
}
