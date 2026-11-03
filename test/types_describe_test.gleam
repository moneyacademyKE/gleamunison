import gleam/option
import gleamunison/ast
import gleamunison/identity
import gleamunison/types

/// Every InferenceError constructor renders as a sentence: no constructor
/// text (TypeMismatch(, TVar(, UnboundVariable() may survive to a user.
/// Types go through the pretty-printer; the TypeMismatch shape
/// "message: expected X, got Y" is preserved byte-for-byte apart from
/// the rendered types.
pub fn describe_inference_error_renders_sentences_test() {
  let assert "unbound variable 3" =
    types.describe_inference_error(types.UnboundVariable(3))

  let assert "argument type mismatch: expected Int, got Text" =
    types.describe_inference_error(types.TypeMismatch(
      expected: ast.Builtin(ast.IntType),
      actual: ast.Builtin(ast.TextType),
      message: "argument type mismatch",
      term: option.None,
    ))

  let assert "infinite type: b refers to variable 1" =
    types.describe_inference_error(types.InfiniteType(1, ast.TypeVar(1)))

  let ability_ref = identity.Ref(identity.hash_bytes(<<"IO">>))
  let assert True =
    types.describe_inference_error(
      types.UnhandledAbility(ast.AbilityRef(ability_ref)),
    )
    == "unhandled ability " <> identity.ref_hex(ability_ref)

  let assert True =
    types.describe_inference_error(
      types.ImpureContext(
        ast.Required([ast.Concrete(ast.AbilityRef(ability_ref))]),
      ),
    )
    == "impure context: required abilities " <> identity.ref_hex(ability_ref)

  let assert "x must be used exactly once" =
    types.describe_inference_error(types.LinearityViolation("x", "exactly once"))
}
