//// Effectful definitions execute through `run`.
////
//// `run` and the REPL are two doors into the same evaluator, so a stored
//// definition that performs `Console print` must actually print through either
//// one. The failure these pin: `call_eval_inner` invoked `'$eval'()` with no
//// ability frames on the stack, so `publish` would admit an effectful
//// definition on a human `io` attestation and `run` would then die with
//// `{unhandled_ability,m_74eafa15,0}` — an admission followed by an inability
//// to execute what was admitted.

import gleamunison/ast
import gleamunison/codebase
import gleamunison/identity.{type DefinitionRef, Local, Ref}
import gleamunison/repl_eval
import gleamunison/run_ref
import gleeunit/should

fn insert(
  cb: codebase.Codebase,
  definition: ast.Definition,
) -> #(codebase.Codebase, DefinitionRef) {
  let ref = Ref(codebase.hash_of_definition(definition))
  let assert Ok(cb) =
    codebase.insert(cb, ast.Unit(root: ref, defs: [#(ref, definition)]))
  #(cb, ref)
}

fn printing(text: BitArray) -> ast.Definition {
  ast.TermDef(
    term: ast.Do(
      ability: repl_eval.ref_for_name("Console"),
      operation: Local(0),
      args: [ast.Text(text)],
    ),
    typ: ast.Builtin(ast.IntType),
  )
}

pub fn an_effectful_definition_runs_with_the_console_handler_test() {
  let #(cb, main_ref) =
    insert(codebase.empty(), printing(<<"héllo from the store">>))
  run_ref.run(codebase.get_adapter(cb), main_ref, []) |> should.equal(Ok("0"))
}

/// The Console operation returns the unit value (0), so an effectful def is
/// still an ordinary value: the handler runs for its effect, not its result.
pub fn console_print_yields_unit_test() {
  let #(cb, main_ref) = insert(codebase.empty(), printing(<<"🦀 crabs">>))
  run_ref.run(codebase.get_adapter(cb), main_ref, []) |> should.equal(Ok("0"))
}

/// A print must not take the evaluation down with it. Text is a BitArray, so a
/// payload that is not valid UTF-8 can reach the handler; rendering it as text
/// would raise inside the frame, and the fix is to fall back to the term form.
pub fn console_print_survives_a_non_utf8_payload_test() {
  let #(cb, main_ref) = insert(codebase.empty(), printing(<<255, 254>>))
  run_ref.run(codebase.get_adapter(cb), main_ref, []) |> should.equal(Ok("0"))
}
