//// Shared ability-call argument checking. Kept apart from general inference:
//// an operation's output is not evidence that its arguments were admitted.

import gleam/list
import gleam/option
import gleam/result
import gleamunison/ast
import gleamunison/infer_unify
import gleamunison/types.{type InferenceError, type TypeCache, TypeMismatch}

pub fn check_args(
  args: List(ast.Term),
  inputs: List(ast.Type),
  cache: TypeCache,
  infer: fn(ast.Term, TypeCache) -> Result(ast.Type, InferenceError),
) -> Result(Nil, InferenceError) {
  case list.length(args) == list.length(inputs) {
    False ->
      Error(TypeMismatch(
        ast.Builtin(ast.ListType),
        ast.Builtin(ast.ListType),
        "ability argument arity mismatch",
        option.None,
      ))
    True ->
      list.try_fold(list.zip(inputs, args), Nil, fn(_, pair) {
        let #(expected, arg) = pair
        use actual <- result.try(infer(arg, cache))
        case infer_unify.unify(expected, actual) {
          Ok(_) -> Ok(Nil)
          Error(_) ->
            Error(TypeMismatch(
              expected,
              actual,
              "ability argument type mismatch",
              option.Some(arg),
            ))
        }
      })
  }
}
