//// Arity: a function is a value. The compiler emits exactly `'$eval'/0`, so
//// an arity-N definition returns a curried fun and `run` applies it one
//// argument at a time. The declared function type is the arity contract: a
//// call with the wrong count is refused before any dependency work.

import gleam/dynamic.{type Dynamic}
import gleam/list
import gleamunison/ast
import gleamunison/codebase
import gleamunison/genesis
import gleamunison/identity.{type DefinitionRef, Local, Ref}
import gleamunison/run_ref
import gleeunit/should

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn arg(value: Int) -> Dynamic

fn insert(
  cb: codebase.Codebase,
  definition: ast.Definition,
) -> #(codebase.Codebase, DefinitionRef) {
  let ref = Ref(codebase.hash_of_definition(definition))
  let assert Ok(cb) =
    codebase.insert(cb, ast.Unit(root: ref, defs: [#(ref, definition)]))
  #(cb, ref)
}

fn int_fn(arity: Int, body: ast.Term) -> ast.Definition {
  let int = ast.Builtin(ast.IntType)
  ast.TermDef(
    term: body,
    typ: ast.Fn(
      params: list.repeat(int, arity),
      result: int,
      requires: ast.Required([]),
    ),
  )
}

pub fn a_one_argument_function_runs_with_an_argument_test() {
  // fn x -> x + x
  let body =
    ast.Lambda(
      binder: Local(0),
      body: ast.Apply(
        function: ast.Apply(
          function: ast.RefTo(genesis.builtin_int_add()),
          arg: ast.LocalVarRef(Local(0)),
        ),
        arg: ast.LocalVarRef(Local(0)),
      ),
    )
  let #(cb, ref) = insert(codebase.empty(), int_fn(1, body))
  run_ref.run(codebase.get_adapter(cb), ref, [arg(21)])
  |> should.equal(Ok("42"))
}

pub fn a_two_argument_function_runs_with_two_arguments_test() {
  // fn a b -> a + b
  let body =
    ast.Lambda(
      binder: Local(0),
      body: ast.Lambda(
        binder: Local(1),
        body: ast.Apply(
          function: ast.Apply(
            function: ast.RefTo(genesis.builtin_int_add()),
            arg: ast.LocalVarRef(Local(0)),
          ),
          arg: ast.LocalVarRef(Local(1)),
        ),
      ),
    )
  let #(cb, ref) = insert(codebase.empty(), int_fn(2, body))
  run_ref.run(codebase.get_adapter(cb), ref, [arg(2), arg(3)])
  |> should.equal(Ok("5"))
}

pub fn passing_an_argument_to_a_value_is_refused_test() {
  let definition = ast.TermDef(term: ast.Int(42), typ: ast.Builtin(ast.IntType))
  let #(cb, ref) = insert(codebase.empty(), definition)
  let assert Error(run_ref.ArityUnavailable(got, expected, supplied)) =
    run_ref.run(codebase.get_adapter(cb), ref, [arg(1)])
  got |> should.equal(ref)
  expected |> should.equal(0)
  supplied |> should.equal(1)
}

pub fn too_few_arguments_is_refused_test() {
  let #(cb, ref) =
    insert(
      codebase.empty(),
      int_fn(2, ast.Lambda(binder: Local(0), body: ast.Int(0))),
    )
  let assert Error(run_ref.ArityUnavailable(_, expected, supplied)) =
    run_ref.run(codebase.get_adapter(cb), ref, [arg(1)])
  expected |> should.equal(2)
  supplied |> should.equal(1)
}

pub fn arity_comes_from_the_declared_type_test() {
  ast.Builtin(ast.IntType) |> run_ref.arity_of |> should.equal(0)
  int_fn(3, ast.Int(0))
  |> fn(def) {
    let assert ast.TermDef(typ: typ, ..) = def
    typ
  }
  |> run_ref.arity_of
  |> should.equal(3)
}

pub fn a_curried_type_counts_its_whole_chain_test() {
  // The surface language curries `(define (f a b) ...)` into nested one-arg
  // lambdas, so a two-parameter definition types as Fn([Int], Fn([Int], Int)).
  let int = ast.Builtin(ast.IntType)
  let curried =
    ast.Fn(
      params: [int],
      result: ast.Fn(params: [int], result: int, requires: ast.Required([])),
      requires: ast.Required([]),
    )
  run_ref.arity_of(curried) |> should.equal(2)
}

pub fn a_curried_two_parameter_definition_runs_test() {
  // Same shape the surface elaborator produces: nested one-arg lambdas.
  let int = ast.Builtin(ast.IntType)
  let body =
    ast.Lambda(
      binder: Local(0),
      body: ast.Lambda(
        binder: Local(1),
        body: ast.Apply(
          function: ast.Apply(
            function: ast.RefTo(genesis.builtin_int_add()),
            arg: ast.LocalVarRef(Local(0)),
          ),
          arg: ast.LocalVarRef(Local(1)),
        ),
      ),
    )
  let definition =
    ast.TermDef(
      term: body,
      typ: ast.Fn(
        params: [int],
        result: ast.Fn(params: [int], result: int, requires: ast.Required([])),
        requires: ast.Required([]),
      ),
    )
  let #(cb, ref) = insert(codebase.empty(), definition)
  run_ref.run(codebase.get_adapter(cb), ref, [arg(40), arg(2)])
  |> should.equal(Ok("42"))
}
