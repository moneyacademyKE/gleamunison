import gleamunison/ast
import gleamunison/identity.{Local}
import gleamunison/inference.{infer_term}
import gleamunison/types.{empty_cache}

pub fn apply_typevar_returns_sentinel_test() {
  let cache = empty_cache()
  // Apply(LocalVarRef(Local(42)), Int(123))
  let app = ast.Apply(function: ast.LocalVarRef(Local(42)), arg: ast.Int(123))
  let assert Ok(ast.TypeVar(-1)) = infer_term(app, cache)
}
