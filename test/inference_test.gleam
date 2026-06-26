import gleamunison/ast
import gleamunison/types.{empty_cache}
import gleamunison/inference.{infer_term}
import gleamunison/identity.{Local}

pub fn apply_typevar_returns_sentinel_test() {
  let cache = empty_cache()
  // Apply(LocalVarRef(Local(42)), Int(123))
  let app = ast.Apply(
    function: ast.LocalVarRef(Local(42)),
    arg: ast.Int(123)
  )
  let assert Ok(ast.TypeVar(-1)) = infer_term(app, cache)
}
