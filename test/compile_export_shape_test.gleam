//// The compiler's export contract: every compiled definition module exports
//// exactly `'$eval'/0` (plus ability op stubs). A function is a value: an
//// arity-N definition compiles to `'$eval'/0` returning a curried fun,
//// applied one argument at a time via `erlang:apply/2`. Locking this
//// contract is what makes `run <hash> a b` a call convention, not a guess.
////
//// On `-no_auto_import`: `compile_source/1` takes no compile options and the
//// export list is a literal in the generated module source
//// (compile.compile_definition), so compile options cannot alter the table.

import gleamunison/ast
import gleamunison/identity.{type DefinitionRef, Local, Ref, hash_bytes}
import gleamunison/loader
import gleeunit/should

fn load(def: ast.Definition, tag: String) -> DefinitionRef {
  let ref = Ref(hash_bytes(<<tag:utf8>>))
  let assert Ok(_) = loader.ensure_loaded(loader.new_loader(), ref, def)
  ref
}

pub fn a_value_definition_exports_only_eval_0_test() {
  let def = ast.TermDef(term: ast.Int(42), typ: ast.Builtin(ast.IntType))
  load(def, "probe-value")
  |> loader.exports
  |> should.equal(Ok([#("$eval", 0)]))
}

pub fn a_two_argument_function_exports_only_eval_0_test() {
  // \a b -> a — arity 2, curried one Lambda per parameter.
  let int = ast.Builtin(ast.IntType)
  let def =
    ast.TermDef(
      term: ast.Lambda(
        binder: Local(0),
        body: ast.Lambda(binder: Local(1), body: ast.LocalVarRef(Local(0))),
      ),
      typ: ast.Fn(params: [int, int], result: int, requires: ast.Required([])),
    )
  load(def, "probe-fn2")
  |> loader.exports
  |> should.equal(Ok([#("$eval", 0)]))
}
