import gleam/dict
import gleam/list
import gleam/option
import gleam/result
import gleamunison/ability_inference
import gleamunison/ast
import gleamunison/bootstrap_types
import gleamunison/identity.{Local}
import gleamunison/infer_helper.{list_all_match}
import gleamunison/infer_unify
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
            False ->
              Error(TypeMismatch(
                t,
                ast.TypeVar(0),
                "element mismatch",
                option.None,
              ))
          }
        }
      }
    }
    ast.LocalVarRef(Local(i)) -> Ok(ast.TypeVar(i))
    ast.Located(inner, _) -> infer_term(inner, cache)
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
          case infer_unify.unify(param_typ, arg_typ) {
            Ok(bindings) -> {
              let ret2 = infer_unify.substitute_all(ret, bindings)
              let rest2 =
                list.map(rest, infer_unify.substitute_all(_, bindings))
              case rest2 {
                [] -> Ok(ret2)
                _ -> Ok(ast.Fn(rest2, ret2, req))
              }
            }
            Error(_) ->
              Error(TypeMismatch(
                param_typ,
                arg_typ,
                "argument type mismatch",
                option.Some(a),
              ))
          }
        }
        ast.TypeVar(_) -> Ok(ast.TypeVar(-1))
        other ->
          case other == bootstrap_types.host_value() {
            True -> Ok(bootstrap_types.host_value())
            False ->
              Error(TypeMismatch(
                ast.Fn([], ast.TypeVar(0), ast.Required([])),
                other,
                "not a function",
                option.Some(f),
              ))
          }
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
    ast.Do(ability, Local(op_idx), args) -> {
      case dict.get(cache.entries, ability) {
        Ok(CTAbility(ops)) -> {
          case list.drop(ops, op_idx) |> list.first {
            Ok(op_typ) ->
              ability_inference.check_args(
                args,
                op_typ.inputs,
                cache,
                infer_term,
              )
              |> result.map(fn(_) { op_typ.output })
            Error(_) ->
              Error(TypeMismatch(
                ast.TypeVar(-1),
                ast.TypeVar(-1),
                "op index out of bounds",
                option.None,
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
fn collect_requirements(
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
    ast.Located(inner, _) -> collect_reqs(inner, cache, bound)
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
