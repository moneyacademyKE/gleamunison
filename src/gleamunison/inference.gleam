import gleam/dict
import gleam/list
import gleam/result
import gleamunison/ast
import gleamunison/identity.{Local}
import gleamunison/infer_helper.{list_all_match, substitute}
import gleamunison/types.{
  type InferenceError, type TypeCache, CTAbility, CTTerm, TypeMismatch,
}

pub fn infer_term(
  term: ast.Term,
  cache: TypeCache,
) -> Result(ast.Type, InferenceError) {
  case term {
    ast.Int(_) -> Ok(ast.Builtin(ast.IntType))
    ast.Float(_) -> Ok(ast.Builtin(ast.FloatType))
    ast.Text(_) -> Ok(ast.Builtin(ast.TextType))
    ast.List(ts) -> {
      case ts {
        [] -> Ok(ast.Builtin(ast.ListType))
        [first, ..rest] -> {
          use t <- result.try(infer_term(first, cache))
          case list_all_match(rest, t, cache, infer_term) {
            True -> Ok(ast.Builtin(ast.ListType))
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
        ast.Fn([param_typ, ..rest], ret, req) -> {
          use arg_typ <- result.try(infer_term(a, cache))
          case param_typ {
            ast.TypeVar(i) -> {
              let ret2 = substitute(ret, i, arg_typ)
              let rest2 = list.map(rest, substitute(_, i, arg_typ))
              case rest2 {
                [] -> Ok(ret2)
                _ -> Ok(ast.Fn(rest2, ret2, req))
              }
            }
            _ ->
              case arg_typ == param_typ {
                True ->
                  case rest {
                    [] -> Ok(ret)
                    _ -> Ok(ast.Fn(rest, ret, req))
                  }
                False ->
                  Error(TypeMismatch(
                    param_typ,
                    arg_typ,
                    "argument type mismatch",
                  ))
              }
          }
        }
        ast.TypeVar(_) -> Ok(ast.TypeVar(-1))
        other ->
          Error(TypeMismatch(
            ast.Fn([], ast.TypeVar(0), ast.Required([])),
            other,
            "not a function",
          ))
      }
    }
    ast.Let(binder: Local(_), value: v, body: b) -> {
      use _ <- result.try(infer_term(v, cache))
      infer_term(b, cache)
    }
    ast.RefTo(ref) -> {
      case dict.get(cache.entries, ref) {
        Ok(CTTerm(t)) -> Ok(t)
        _ -> Ok(ast.TypeVar(-1))
      }
    }
    ast.Do(ability, Local(op_idx), _) -> {
      case dict.get(cache.entries, ability) {
        Ok(CTAbility(ops)) -> {
          case list.drop(ops, op_idx) |> list.first {
            Ok(op_typ) -> Ok(op_typ.output)
            Error(_) ->
              Error(TypeMismatch(
                ast.TypeVar(-1),
                ast.TypeVar(-1),
                "op index out of bounds",
              ))
          }
        }
        _ -> Ok(ast.TypeVar(-1))
      }
    }
    ast.Handle(computation, _, _) -> infer_term(computation, cache)
    ast.Match(_, cases) -> {
      case cases {
        [] -> Ok(ast.TypeVar(-1))
        [first, ..] -> infer_term(first.body, cache)
      }
    }
    ast.Construct(ctor_ref, _) -> {
      case dict.get(cache.entries, ctor_ref) {
        Ok(CTTerm(t)) -> Ok(t)
        _ -> Ok(ast.TypeVar(-1))
      }
    }
  }
}
