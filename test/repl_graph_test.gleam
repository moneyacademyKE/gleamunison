import gleam/string
import gleamunison/elab_types.{
  type SurfaceDef, SInt, SLambda, SVar, SurfaceTermDef,
}
import gleamunison/repl_graph
import gleamunison/types.{empty_cache}
import gleeunit/should

fn test_defs() -> List(#(String, SurfaceDef)) {
  [
    #("one", SurfaceTermDef(SInt(1))),
    #("inc", SurfaceTermDef(SLambda("x", SVar("one")))),
  ]
}

/// `dependents <name>` answers from the datalog index.
pub fn dependents_command_test() {
  let assert Ok(out) =
    repl_graph.try_handle("dependents one", empty_cache(), test_defs())
  string.contains(out, "inc") |> should.be_true
}

/// `dependencies <name>` answers from the datalog index.
pub fn dependencies_command_test() {
  let assert Ok(out) =
    repl_graph.try_handle("dependencies inc", empty_cache(), test_defs())
  string.contains(out, "one") |> should.be_true
}

/// `view <name>` shows kind, content hash, and inferred type.
pub fn view_command_test() {
  let assert Ok(out) =
    repl_graph.try_handle("view one", empty_cache(), test_defs())
  string.contains(out, "term") |> should.be_true
  string.contains(out, "Int") |> should.be_true
}

/// view of a missing name says so, not crashes.
pub fn view_missing_name_test() {
  let assert Ok(out) =
    repl_graph.try_handle("view nope", empty_cache(), test_defs())
  string.contains(out, "not found") |> should.be_true
}

/// Non-commands pass through: expressions, help, exit.
pub fn non_commands_pass_through_test() {
  repl_graph.try_handle("(add 1 2)", empty_cache(), test_defs())
  |> should.equal(Error(Nil))
  repl_graph.try_handle("help", empty_cache(), test_defs())
  |> should.equal(Error(Nil))
  repl_graph.try_handle("exit", empty_cache(), test_defs())
  |> should.equal(Error(Nil))
}

/// The command names alone (no argument) are a usage error, not a pass-through.
pub fn bare_command_is_usage_error_test() {
  let assert Ok(out) = repl_graph.try_handle("view", empty_cache(), test_defs())
  string.contains(out, "usage") |> should.be_true
}
