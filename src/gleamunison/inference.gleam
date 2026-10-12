import gleam/dict
import gleam/list
import gleam/option
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
      |> result.map(fn(ret) {
        ast.Fn(
          [ast.TypeVar(i)],
          ret,
          ast.Required(collect_requirements(body, cache)),
        )
      })
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
    ast.Hole -> Ok(ast.TypeVar(-1))
    ast.Use(_, _call, body) -> infer_term(body, cache)
  }
}

/// Collect the abilities a term's evaluation may perform: abilities named
/// by `Do` nodes on the evaluation spine, minus those bound by an enclosing
/// `Handle`, plus the declared requirements of referenced definitions.
///
/// Deliberate under-approximation: we do not descend into nested `Lambda`
/// bodies (an unapplied closure performs nothing), and locally-bound
/// closures called later are not tracked. Documented in docs/adr (effects
/// are dynamic by design); the requirement set is a lower bound.
pub fn collect_requirements(
  term: ast.Term,
  cache: TypeCache,
) -> List(ast.ReqElement) {
  collect_reqs(term, cache, [])
  |> list.unique
}

fn collect_reqs(
  term: ast.Term,
  cache: TypeCache,
  bound: List(identity.DefinitionRef),
) -> List(ast.ReqElement) {
  case term {
    ast.Int(_) | ast.Float(_) | ast.Text(_) | ast.Hole | ast.LocalVarRef(_) -> []
    ast.RefTo(ref) ->
      case dict.get(cache.entries, ref) {
        Ok(CTTerm(ast.Fn(_, _, ast.Required(reqs)))) -> reqs
        _ -> []
      }
    ast.List(ts) -> list.flat_map(ts, fn(t) { collect_reqs(t, cache, bound) })
    ast.Apply(function: f, arg: a) ->
      list.append(collect_reqs(f, cache, bound), collect_reqs(a, cache, bound))
    ast.Lambda(..) -> []
    ast.Let(binder: _, value: v, body: b) ->
      list.append(collect_reqs(v, cache, bound), collect_reqs(b, cache, bound))
    ast.Match(scrutinee: s, cases:) ->
      list.append(
        collect_reqs(s, cache, bound),
        list.flat_map(cases, fn(c) {
          let guard_reqs = case c.guard {
            option.Some(ast.GuardTerm(t)) -> collect_reqs(t, cache, bound)
            option.None -> []
          }
          list.append(guard_reqs, collect_reqs(c.body, cache, bound))
        }),
      )
    ast.Do(ability, _, args) ->
      case list.contains(bound, ability) {
        True -> list.flat_map(args, fn(a) { collect_reqs(a, cache, bound) })
        False -> [
          ast.Concrete(ast.AbilityRef(decl: ability)),
          ..list.flat_map(args, fn(a) { collect_reqs(a, cache, bound) })
        ]
      }
    ast.Handle(computation: comp, handler: h, ability:) ->
      list.append(
        collect_reqs(comp, cache, [ability, ..bound]),
        collect_reqs(h, cache, bound),
      )
    ast.Construct(_, args) ->
      list.flat_map(args, fn(a) { collect_reqs(a, cache, bound) })
    ast.Use(_, call, body) ->
      list.append(
        collect_reqs(call, cache, bound),
        collect_reqs(body, cache, bound),
      )
  }
}

pub fn check_linearity(
  term: ast.Term,
  cache: TypeCache,
) -> Result(Nil, InferenceError) {
  let _ = cache
  case term {
    ast.Lambda(..) -> {
      let ast.Lambda(binder: _, body: b) = term
      check_linearity(b, cache)
    }
    ast.Let(..) -> {
      let ast.Let(binder: _, value: _, body: b) = term
      check_linearity(b, cache)
    }
    ast.Match(..) -> {
      let ast.Match(scrutinee: _, cases: cases) = term
      case cases {
        [] -> Ok(Nil)
        [first, ..rest] ->
          case check_linearity(first.body, cache) {
            Error(e) -> Error(e)
            Ok(_) ->
              list.fold(rest, Ok(Nil), fn(acc, c) {
                case acc {
                  Error(_) -> acc
                  Ok(_) -> check_linearity(c.body, cache)
                }
              })
          }
      }
    }
    ast.Apply(..) -> {
      let ast.Apply(function: f, arg: a) = term
      case check_linearity(f, cache) {
        Error(e) -> Error(e)
        Ok(_) -> check_linearity(a, cache)
      }
    }
    ast.Do(..) -> {
      let ast.Do(ability: _, operation: _, args: args) = term
      list.fold(args, Ok(Nil), fn(acc, a) {
        case acc {
          Error(_) -> acc
          Ok(_) -> check_linearity(a, cache)
        }
      })
    }
    ast.Handle(..) -> {
      let ast.Handle(computation: comp, handler: handler, ability: _) = term
      case check_linearity(comp, cache) {
        Error(e) -> Error(e)
        Ok(_) -> check_linearity(handler, cache)
      }
    }
    _ -> Ok(Nil)
  }
}
