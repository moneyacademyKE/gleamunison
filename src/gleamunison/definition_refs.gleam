//// Every content ref a definition mentions.
////
//// The store is a graph keyed by ref, so loading one definition honestly means
//// loading what it points at first. This module is that edge list and nothing
//// else: no I/O, no ordering policy, no notion of what "loaded" means. Ordering
//// belongs to the caller that walks the closure.

import gleam/list
import gleam/option
import gleamunison/ast
import gleamunison/identity.{type DefinitionRef}

pub fn refs_of_definition(definition: ast.Definition) -> List(DefinitionRef) {
  let refs = case definition {
    ast.TermDef(term:, typ:) -> list.append(refs_of_term(term), refs_of_type(typ))
    ast.TypeDef(ast.Structural(constructors:, ..)) ->
      refs_of_constructors(constructors)
    ast.TypeDef(ast.Unique(constructors:, ..)) ->
      refs_of_constructors(constructors)
    ast.AbilityDecl(ast.AbilityDeclaration(operations:, ..)) ->
      list.flat_map(operations, refs_of_operation)
  }
  list.unique(refs)
}

pub fn refs_of_term(term: ast.Term) -> List(DefinitionRef) {
  case term {
    ast.Located(inner:, ..) -> refs_of_term(inner)
    ast.Int(_) | ast.Float(_) | ast.Text(_) | ast.Hole | ast.LocalVarRef(_) -> []
    ast.List(terms) -> list.flat_map(terms, refs_of_term)
    ast.Lambda(body:, ..) -> refs_of_term(body)
    ast.Apply(function:, arg:) ->
      list.append(refs_of_term(function), refs_of_term(arg))
    ast.Let(value:, body:, ..) ->
      list.append(refs_of_term(value), refs_of_term(body))
    ast.RefTo(ref) -> [ref]
    ast.Match(scrutinee:, cases:) ->
      list.append(
        refs_of_term(scrutinee),
        list.flat_map(cases, refs_of_case),
      )
    ast.Do(ability:, args:, ..) ->
      [ability, ..list.flat_map(args, refs_of_term)]
    ast.Handle(computation:, handler:, ability:) ->
      [ability, ..list.append(refs_of_term(computation), refs_of_term(handler))]
    ast.Construct(ctor_ref:, args:) ->
      [ctor_ref, ..list.flat_map(args, refs_of_term)]
    ast.Use(call:, body:, ..) ->
      list.append(refs_of_term(call), refs_of_term(body))
  }
}

fn refs_of_case(case_: ast.Case) -> List(DefinitionRef) {
  let guard_refs = case case_.guard {
    option.Some(ast.GuardTerm(term)) -> refs_of_term(term)
    option.None -> []
  }
  list.flatten([
    refs_of_pattern(case_.pattern),
    guard_refs,
    refs_of_term(case_.body),
  ])
}

pub fn refs_of_pattern(pattern: ast.Pattern) -> List(DefinitionRef) {
  case pattern {
    ast.PatVar(_)
    | ast.PatInt(_)
    | ast.PatText(_)
    | ast.PatCons(_, _)
    | ast.PatEmptyList -> []
    ast.PatAs(inner:, ..) -> refs_of_pattern(inner)
    ast.PatConstructor(ctor_ref:, args:) ->
      [ctor_ref, ..list.flat_map(args, refs_of_pattern)]
  }
}

pub fn refs_of_type(typ: ast.Type) -> List(DefinitionRef) {
  case typ {
    ast.Builtin(_) | ast.TypeVar(_) | ast.AbilityVar(_) -> []
    ast.Fn(params:, result:, requires:) ->
      list.flatten([
        list.flat_map(params, refs_of_type),
        refs_of_type(result),
        refs_of_requirement(requires),
      ])
    ast.App(name:, args:) -> [name, ..list.flat_map(args, refs_of_type)]
  }
}

fn refs_of_requirement(requirement: ast.Requirement) -> List(DefinitionRef) {
  let ast.Required(elements) = requirement
  list.filter_map(elements, fn(element) {
    case element {
      ast.ReqVar(_) -> Error(Nil)
      ast.Concrete(ast.AbilityRef(decl)) -> Ok(decl)
    }
  })
}

pub fn refs_of_type_ref(type_ref: ast.TypeRef) -> List(DefinitionRef) {
  case type_ref {
    ast.TypeRefVar(_) | ast.TypeRefBuiltin(_) -> []
    ast.TypeCon(ref) -> [ref]
  }
}

fn refs_of_constructors(
  constructors: List(ast.Constructor),
) -> List(DefinitionRef) {
  list.flat_map(constructors, fn(constructor) {
    let ast.Constructor(_, args) = constructor
    list.flat_map(args, refs_of_type_ref)
  })
}

fn refs_of_operation(operation: ast.Operation) -> List(DefinitionRef) {
  let ast.Operation(_, inputs, output) = operation
  list.append(list.flat_map(inputs, refs_of_type_ref), refs_of_type_ref(output))
}
