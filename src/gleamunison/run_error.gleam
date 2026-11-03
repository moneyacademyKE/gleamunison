//// Why a ref did not run, and how to say it to a person.
////
//// The vocabulary is one type in one module because three concerns share it:
//// resolving the closure, executing the definition, and inspecting it without
//// executing. Splitting those into separate modules with separate error types
//// would only add translation layers between them.

import gleam/int
import gleamunison/codebase
import gleamunison/identity.{type DefinitionRef}

pub type RunError {
  Missing(ref: DefinitionRef)
  Unreadable(ref: DefinitionRef, reason: String)
  NotExecutable(ref: DefinitionRef, kind: String)
  LoadFailed(ref: DefinitionRef, reason: String)
  Cycle(ref: DefinitionRef)
  ArityUnavailable(ref: DefinitionRef, expected: Int, supplied: Int)
  NoEvidence(ref: DefinitionRef, reason: String)
  EvaluationFailed(ref: DefinitionRef, reason: String)
}

fn hex(ref: DefinitionRef) -> String {
  identity.ref_hex(ref)
}

pub fn read_error(ref: DefinitionRef, error: codebase.ReadError) -> RunError {
  case error {
    codebase.NotFound(_) -> Missing(ref)
    other -> Unreadable(ref, codebase.describe_read_error(other))
  }
}

pub fn describe(error: RunError) -> String {
  case error {
    Missing(ref) ->
      "not in the store: " <> hex(ref) <> " (publish it or sync it first)"
    Unreadable(ref, reason) -> "cannot read " <> hex(ref) <> ": " <> reason
    NotExecutable(ref, kind) ->
      hex(ref) <> " is " <> kind <> ", not a runnable term"
    LoadFailed(ref, reason) -> "cannot load " <> hex(ref) <> ": " <> reason
    Cycle(ref) ->
      "dependency cycle at "
      <> hex(ref)
      <> "; the store disagrees with its refs"
    ArityUnavailable(ref, expected, supplied) ->
      case supplied == 0 {
        True ->
          hex(ref)
          <> " is a function of arity "
          <> int.to_string(expected)
          <> "; pass "
          <> int.to_string(expected)
          <> " argument(s), or inspect it without calling"
        False ->
          hex(ref)
          <> " expects "
          <> int.to_string(expected)
          <> " argument(s), got "
          <> int.to_string(supplied)
      }
    NoEvidence(ref, reason) -> hex(ref) <> " is not verified: " <> reason
    EvaluationFailed(ref, reason) ->
      "evaluation of " <> hex(ref) <> " failed: " <> reason
  }
}
