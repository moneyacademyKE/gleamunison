import gleam/dict
import gleam/list
import gleam/result
import gleamunison/identity.{Local}
import gleamunison/ast as ast
import gleamunison/types.{type TypeCache, type InferenceError, CTTerm, TypeMismatch}

pub fn infer_term(term: ast.Term, cache: TypeCache) -> Result(ast.Type, InferenceError) {
  case term {
    ast.Int(_) -> Ok(ast.Builtin(ast.IntType))
    ast.Float(_) -> Ok(ast.Builtin(ast.FloatType))
    ast.Text(_) -> Ok(ast.Builtin(ast.TextType))
    ast.List(ts) -> {
      case ts {
        [] -> Ok(ast.TypeVar(0))
        [first, ..rest] -> {
          use t <- result.try(infer_term(first, cache))
          case list_all_match(rest, t, cache) {
            True -> Ok(ast.TypeVar(0))
            False -> Error(TypeMismatch(t, ast.TypeVar(0), "element mismatch"))
          }
        }
      }
    }
    ast.LocalVarRef(Local(i)) -> Ok(ast.TypeVar(i))
    ast.Lambda(binder: Local(i), body:) ->
      infer_term(body, cache)
      |> result.map(fn(ret) { ast.Fn([ast.TypeVar(i)], ret, ast.Required([])) })
    ast.Apply(function: f, arg: a) -> {
      use ft <- result.try(infer_term(f, cache))
      case ft {
        ast.Fn([ast.TypeVar(i)], ret, _) ->
          infer_term(a, cache) |> result.map(fn(arg_typ) { substitute(ret, i, arg_typ) })
        ast.TypeVar(_) -> Ok(ast.TypeVar(0))
        other -> Error(TypeMismatch(ast.Fn([], ast.TypeVar(0), ast.Required([])), other, "not a function"))
      }
    }
    ast.Let(binder: Local(_), value: v, body: b) -> {
      use _ <- result.try(infer_term(v, cache))
      infer_term(b, cache)
    }
    ast.RefTo(ref) -> {
      case dict.get(cache.entries, ref) {
        Ok(CTTerm(t)) -> Ok(t)
        _ -> Ok(ast.TypeVar(0))
      }
    }
    _ -> Ok(ast.TypeVar(0))
  }
}

fn substitute(typ: ast.Type, target_index: Int, replacement: ast.Type) -> ast.Type {
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

fn list_all_match(ts: List(ast.Term), t: ast.Type, cache: TypeCache) -> Bool {
  case ts {
    [] -> True
    [first, ..rest] -> {
      case infer_term(first, cache) {
        Ok(t2) -> t == t2 && list_all_match(rest, t, cache)
        Error(_) -> False
      }
    }
  }
}
