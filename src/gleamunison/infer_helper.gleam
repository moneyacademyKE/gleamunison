import gleam/list
import gleamunison/ast
import gleamunison/types.{type TypeCache}

pub fn substitute(typ: ast.Type, target_index: Int, replacement: ast.Type) -> ast.Type {
  case typ {
    ast.TypeVar(i) -> {
      case i == target_index {
        True -> replacement
        False -> typ
      }
    }
    ast.Fn(params, result, requires) ->
      ast.Fn(list.map(params, substitute(_, target_index, replacement)), substitute(result, target_index, replacement), requires)
    ast.App(name, args) ->
      ast.App(name, list.map(args, substitute(_, target_index, replacement)))
    _ -> typ
  }
}

pub fn list_all_match(
  ts: List(ast.Term),
  t: ast.Type,
  cache: TypeCache,
  infer_fn: fn(ast.Term, TypeCache) -> Result(ast.Type, types.InferenceError),
) -> Bool {
  case ts {
    [] -> True
    [first, ..rest] -> {
      case infer_fn(first, cache) {
        Ok(t2) -> t == t2 && list_all_match(rest, t, cache, infer_fn)
        Error(_) -> False
      }
    }
  }
}
