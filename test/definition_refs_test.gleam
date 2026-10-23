//// The dependency edge list: what a definition points at. Every case here is
//// a ref the store must resolve before the definition can run.

import gleam/option
import gleamunison/ast
import gleamunison/definition_refs
import gleamunison/identity.{Local, Ref, hash_bytes}
import gleeunit/should

pub fn refs_of_a_term_definition_are_deduped_test() {
  let a = Ref(hash_bytes(<<"a">>))
  let b = Ref(hash_bytes(<<"b">>))
  // `a` is referenced twice; the closure only needs it once.
  let term =
    ast.Apply(
      function: ast.Lambda(binder: Local(0), body: ast.RefTo(a)),
      arg: ast.Apply(function: ast.RefTo(b), arg: ast.RefTo(a)),
    )
  let definition = ast.TermDef(term: term, typ: ast.Builtin(ast.IntType))
  definition_refs.refs_of_definition(definition)
  |> should.equal([a, b])
}

pub fn refs_of_a_definition_without_refs_is_empty_test() {
  let definition = ast.TermDef(term: ast.Int(1), typ: ast.Builtin(ast.IntType))
  definition_refs.refs_of_definition(definition) |> should.equal([])
}

pub fn refs_of_a_pattern_constructor_are_collected_test() {
  let constructor = Ref(hash_bytes(<<"ctor">>))
  let term =
    ast.Match(scrutinee: ast.Int(1), cases: [
      ast.Case(
        pattern: ast.PatConstructor(ctor_ref: constructor, args: [ast.PatInt(2)]),
        guard: option.None,
        body: ast.Int(3),
      ),
    ])
  let definition = ast.TermDef(term: term, typ: ast.Builtin(ast.IntType))
  definition_refs.refs_of_definition(definition)
  |> should.equal([constructor])
}

pub fn refs_of_a_concrete_ability_requirement_are_collected_test() {
  let ability = Ref(hash_bytes(<<"ability">>))
  let typ =
    ast.Fn(
      params: [ast.Builtin(ast.IntType)],
      result: ast.Builtin(ast.IntType),
      requires: ast.Required([ast.Concrete(ast.AbilityRef(ability))]),
    )
  let definition = ast.TermDef(term: ast.Int(1), typ: typ)
  definition_refs.refs_of_definition(definition) |> should.equal([ability])
}

pub fn refs_of_a_type_definition_constructor_args_are_collected_test() {
  let argument = Ref(hash_bytes(<<"type-argument">>))
  let definition =
    ast.TypeDef(
      ast.Structural(Local(0), [], [
        ast.Constructor(Local(1), [ast.TypeCon(argument)]),
      ]),
    )
  definition_refs.refs_of_definition(definition) |> should.equal([argument])
}
