//// Run by hash: resolve the closure, load it, execute it. These tests use an
//// in-memory store, which is the same adapter contract dets satisfies.

import gleamunison/ast
import gleamunison/codebase
import gleamunison/genesis
import gleamunison/identity.{type DefinitionRef, Local, Ref, hash_bytes}
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

fn int_fn_returning(value: Int) -> ast.Definition {
  ast.TermDef(
    term: ast.Lambda(binder: Local(0), body: ast.Int(value)),
    typ: ast.Fn(
      params: [ast.Builtin(ast.IntType)],
      result: ast.Builtin(ast.IntType),
      requires: ast.Required([]),
    ),
  )
}

pub fn a_stored_dependency_resolves_and_executes_test() {
  let #(cb, dep_ref) = insert(codebase.empty(), int_fn_returning(7))
  let main =
    ast.TermDef(
      term: ast.Apply(function: ast.RefTo(dep_ref), arg: ast.Int(0)),
      typ: ast.Builtin(ast.IntType),
    )
  let #(cb, main_ref) = insert(cb, main)
  run_ref.run(codebase.get_adapter(cb), main_ref) |> should.equal(Ok("7"))
}

pub fn a_genesis_builtin_needs_no_store_entry_test() {
  let main =
    ast.TermDef(
      term: ast.Apply(
        function: ast.Apply(
          function: ast.RefTo(genesis.builtin_int_add()),
          arg: ast.Int(1),
        ),
        arg: ast.Int(2),
      ),
      typ: ast.Builtin(ast.IntType),
    )
  let #(cb, main_ref) = insert(codebase.empty(), main)
  run_ref.run(codebase.get_adapter(cb), main_ref) |> should.equal(Ok("3"))
}

pub fn a_missing_dependency_names_the_ref_test() {
  let absent = Ref(hash_bytes(<<"absent-dependency">>))
  let main =
    ast.TermDef(
      term: ast.Apply(function: ast.RefTo(absent), arg: ast.Int(1)),
      typ: ast.Builtin(ast.IntType),
    )
  let #(cb, main_ref) = insert(codebase.empty(), main)
  let assert Error(run_ref.Missing(got)) =
    run_ref.run(codebase.get_adapter(cb), main_ref)
  got |> should.equal(absent)
}

pub fn an_absent_root_ref_is_missing_test() {
  let absent = Ref(hash_bytes(<<"absent-root">>))
  let assert Error(run_ref.Missing(got)) =
    run_ref.run(codebase.get_adapter(codebase.empty()), absent)
  got |> should.equal(absent)
}

pub fn a_type_definition_refuses_to_execute_test() {
  let definition = ast.TypeDef(ast.Structural(Local(0), [], []))
  let #(cb, ref) = insert(codebase.empty(), definition)
  let assert Error(run_ref.NotExecutable(got, _)) =
    run_ref.run(codebase.get_adapter(cb), ref)
  got |> should.equal(ref)
}
