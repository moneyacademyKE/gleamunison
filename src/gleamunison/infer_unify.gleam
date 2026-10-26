//// Structural unification with fresh inference variables. Expected type
//// variables are shifted above every source-local variable before matching;
//// a binding therefore cannot accidentally capture a lambda's local type.

import gleam/list
import gleamunison/ast
import gleamunison/bootstrap_types as bt
import gleamunison/infer_helper.{substitute}

pub type Bindings =
  List(#(Int, ast.Type))

pub fn substitute_all(typ: ast.Type, bindings: Bindings) -> ast.Type {
  list.fold(bindings, typ, fn(current, binding) {
    substitute(current, binding.0, binding.1)
  })
}

pub fn unify(expected: ast.Type, actual: ast.Type) -> Result(Bindings, Nil) {
  let offset = max_type_var(expected, max_type_var(actual, 0)) + 1
  let fresh_expected = shift(expected, offset)
  use bindings <- result_try(unify_with(fresh_expected, actual, [], offset))
  Ok(list.map(bindings, fn(binding) { #(binding.0 - offset, binding.1) }))
}

fn unify_with(
  expected: ast.Type,
  actual: ast.Type,
  bindings: Bindings,
  offset: Int,
) -> Result(Bindings, Nil) {
  let expected = substitute_all(expected, bindings)
  let actual = substitute_all(actual, bindings)
  case
    expected == actual
    || expected == bt.host_value()
    || actual == bt.host_value()
  {
    True -> Ok(bindings)
    False ->
      case expected, actual {
        ast.TypeVar(index), _ ->
          case index >= offset {
            True -> bind(index, actual, bindings)
            False -> Ok(bindings)
          }
        _, ast.TypeVar(_) -> Ok(bindings)
        ast.Fn(expected_params, expected_result, _),
          ast.Fn(actual_params, actual_result, _)
        ->
          case list.length(expected_params) == list.length(actual_params) {
            False -> Error(Nil)
            True -> {
              use next <- result_try(unify_lists(
                expected_params,
                actual_params,
                bindings,
                offset,
              ))
              unify_with(expected_result, actual_result, next, offset)
            }
          }
        ast.App(expected_ref, expected_args), ast.App(actual_ref, actual_args)
        ->
          case
            expected_ref == actual_ref
            && list.length(expected_args) == list.length(actual_args)
          {
            False -> Error(Nil)
            True -> unify_lists(expected_args, actual_args, bindings, offset)
          }
        ast.App(expected_ref, _), ast.Builtin(ast.ListType)
        | ast.Builtin(ast.ListType), ast.App(expected_ref, _)
        ->
          case expected_ref == bt.named("List") {
            True -> Ok(bindings)
            False -> Error(Nil)
          }
        ast.Builtin(expected_builtin), ast.Builtin(actual_builtin)
          if expected_builtin == actual_builtin
        -> Ok(bindings)
        _, _ -> Error(Nil)
      }
  }
}

fn unify_lists(
  expected: List(ast.Type),
  actual: List(ast.Type),
  bindings: Bindings,
  offset: Int,
) -> Result(Bindings, Nil) {
  case expected, actual {
    [], [] -> Ok(bindings)
    [e, ..es], [a, ..remaining] -> {
      use next <- result_try(unify_with(e, a, bindings, offset))
      unify_lists(es, remaining, next, offset)
    }
    _, _ -> Error(Nil)
  }
}

fn bind(
  index: Int,
  replacement: ast.Type,
  bindings: Bindings,
) -> Result(Bindings, Nil) {
  let updated =
    list.map(bindings, fn(binding) {
      #(binding.0, substitute(binding.1, index, replacement))
    })
  Ok([#(index, replacement), ..updated])
}

fn shift(typ: ast.Type, offset: Int) -> ast.Type {
  case typ {
    ast.TypeVar(index) ->
      case index >= 0 {
        True -> ast.TypeVar(index + offset)
        False -> typ
      }
    ast.Fn(params, result, requires) ->
      ast.Fn(
        list.map(params, shift(_, offset)),
        shift(result, offset),
        requires,
      )
    ast.App(ref, args) -> ast.App(ref, list.map(args, shift(_, offset)))
    _ -> typ
  }
}

fn max_type_var(typ: ast.Type, current: Int) -> Int {
  case typ {
    ast.TypeVar(index) ->
      case index > current {
        True -> index
        False -> current
      }
    ast.Fn(params, result, _) ->
      list.fold([result, ..params], current, fn(acc, item) {
        max_type_var(item, acc)
      })
    ast.App(_, args) ->
      list.fold(args, current, fn(acc, item) { max_type_var(item, acc) })
    _ -> current
  }
}

fn result_try(
  result: Result(a, e),
  next: fn(a) -> Result(b, e),
) -> Result(b, e) {
  case result {
    Ok(value) -> next(value)
    Error(error) -> Error(error)
  }
}
