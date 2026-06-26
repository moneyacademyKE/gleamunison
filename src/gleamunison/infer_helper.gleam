import gleam/dict
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

pub fn normalize_type(t: ast.Type) -> ast.Type {
  normalize_type_state(t, dict.new(), 0).0
}

fn normalize_type_state(
  t: ast.Type,
  m: dict.Dict(Int, Int),
  next: Int,
) -> #(ast.Type, dict.Dict(Int, Int), Int) {
  case t {
    ast.TypeVar(i) -> {
      case dict.get(m, i) {
        Ok(new_i) -> #(ast.TypeVar(new_i), m, next)
        Error(_) -> #(ast.TypeVar(next), dict.insert(m, i, next), next + 1)
      }
    }
    ast.AbilityVar(i) -> #(ast.AbilityVar(i), m, next)
    ast.Fn(params, result, requires) -> {
      let #(params2, m2, next2) =
        list.fold(params, #([], m, next), fn(acc, p) {
          let #(acc_params, acc_m, acc_next) = acc
          let #(p2, new_m, new_next) = normalize_type_state(p, acc_m, acc_next)
          #([p2, ..acc_params], new_m, new_next)
        })
      let params2 = list.reverse(params2)
      let #(result2, m3, next3) = normalize_type_state(result, m2, next2)
      #(ast.Fn(params2, result2, requires), m3, next3)
    }
    ast.App(name, args) -> {
      let #(args2, m2, next2) =
        list.fold(args, #([], m, next), fn(acc, a) {
          let #(acc_args, acc_m, acc_next) = acc
          let #(a2, new_m, new_next) = normalize_type_state(a, acc_m, acc_next)
          #([a2, ..acc_args], new_m, new_next)
        })
      let args2 = list.reverse(args2)
      #(ast.App(name, args2), m2, next2)
    }
    ast.Builtin(_) -> #(t, m, next)
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
        Ok(t2) ->
          normalize_type(t) == normalize_type(t2)
          && list_all_match(rest, t, cache, infer_fn)
        Error(_) -> False
      }
    }
  }
}
