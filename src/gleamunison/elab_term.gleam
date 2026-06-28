import gleam/dict
import gleam/option
import gleam/list
import gleam/result
import gleamunison/ast
import gleamunison/elab_ctx.{type ElabCtx, ElabCtx, add_binding, lookup_binding}
import gleamunison/elab_pat.{elaborate_pattern}
import gleamunison/elab_types.{
  type ElaborateError, type SCase, type SurfaceTerm, MissingAbilityDecl,
  NameNotFound, SApply, SCase, SConstruct, SDo, SFloat, SGuardGuard, SHandle,
  SHole, SInt, SLambda, SLabeledFn, SLet, SList, SMatch, SRef, SText, SUse,
  SVar, UnknownOperation, UnsupportedTypeRef,
}
import gleamunison/identity.{Local}

pub fn elaborate_term(
  term: SurfaceTerm,
  ctx: ElabCtx,
) -> Result(#(ElabCtx, ast.Term), ElaborateError) {
  case term {
    SInt(n) -> Ok(#(ctx, ast.Int(n)))
    SFloat(f) -> Ok(#(ctx, ast.Float(f)))
    SText(b) -> Ok(#(ctx, ast.Text(b)))
    SList(ts) -> {
      case
        list.try_fold(ts, #(ctx, []), fn(acc, t) {
          let #(c_ctx, acc_ts) = acc
          use #(n_ctx, term) <- result.try(elaborate_term(t, c_ctx))
          Ok(#(n_ctx, [term, ..acc_ts]))
        })
      {
        Ok(#(final_ctx, terms)) ->
          Ok(#(final_ctx, ast.List(list.reverse(terms))))
        Error(e) -> Error(e)
      }
    }
    SVar(name) -> {
      case lookup_binding(ctx, name) {
        Ok(lv) -> Ok(#(ctx, ast.LocalVarRef(lv)))
        Error(_) -> {
          dict.get(ctx.names, name)
          |> result.map(fn(r) { #(ctx, ast.RefTo(r)) })
          |> result.replace_error(NameNotFound(name))
        }
      }
    }
    SRef(r) -> Ok(#(ctx, ast.RefTo(r)))
    SApply(f, a) -> {
      use #(ctx2, f2) <- result.try(elaborate_term(f, ctx))
      use #(ctx3, a2) <- result.try(elaborate_term(a, ctx2))
      Ok(#(ctx3, ast.Apply(f2, a2)))
    }
    SLambda(p, b) -> {
      let #(ctx2, lv) = add_binding(ctx, p)
      use #(ctx3, b2) <- result.try(elaborate_term(b, ctx2))
      Ok(#(ctx3, ast.Lambda(lv, b2)))
    }
    SLet(n, v, b) -> {
      use #(ctx2, v2) <- result.try(elaborate_term(v, ctx))
      let #(ctx3, lv) = add_binding(ctx2, n)
      use #(ctx4, b2) <- result.try(elaborate_term(b, ctx3))
      Ok(#(ctx4, ast.Let(lv, v2, b2)))
    }
    SMatch(s, cs) -> {
      use #(ctx2, s2) <- result.try(elaborate_term(s, ctx))
      use #(ctx3, els) <- result.try(elaborate_cases(cs, ctx2, []))
      Ok(#(ctx3, ast.Match(s2, els)))
    }
    SDo(ab, op, args) -> {
      use ab_ref <- result.try(
        dict.get(ctx.abilities, ab)
        |> result.replace_error(MissingAbilityDecl(ab)),
      )
      use terms <- result.try(
        list.try_map(args, fn(a) {
          elaborate_term(a, ctx) |> result.map(fn(p) { p.1 })
        }),
      )
      use op_idx <- result.try(
        dict.get(ctx.ops, #(ab, op))
        |> result.replace_error(UnknownOperation(ab, op)),
      )
      Ok(#(ctx, ast.Do(ab_ref, Local(op_idx), terms)))
    }
    SHandle(c, h, ab) -> {
      use ab_ref <- result.try(
        dict.get(ctx.abilities, ab)
        |> result.replace_error(MissingAbilityDecl(ab)),
      )
      use #(ctx2, comp) <- result.try(elaborate_term(c, ctx))
      use #(ctx3, hand) <- result.try(elaborate_term(h, ctx2))
      Ok(#(ctx3, ast.Handle(comp, hand, ab_ref)))
    }
    SConstruct(name, args) -> {
      use ctor_ref <- result.try(
        dict.get(ctx.names, name) |> result.replace_error(NameNotFound(name)),
      )
      use #(ctx2, elaborated_args) <- result.try(
        list.try_fold(args, #(ctx, []), fn(acc, arg) {
          let #(c_ctx, acc_args) = acc
          use #(n_ctx, term) <- result.try(elaborate_term(arg, c_ctx))
          Ok(#(n_ctx, [term, ..acc_args]))
        }),
      )
      Ok(#(ctx2, ast.Construct(ctor_ref, list.reverse(elaborated_args))))
    }
    SHole -> Ok(#(ctx, ast.Hole))
    SGuardGuard(_) -> Error(UnsupportedTypeRef("SGuardGuard not a standalone term"))
    SUse(binder, call_expr, body_expr) -> {
      use #(ctx2, call_elab) <- result.try(elaborate_term(call_expr, ctx))
      let #(ctx3, lv) = add_binding(ctx2, binder)
      use #(ctx4, body_elab) <- result.try(elaborate_term(body_expr, ctx3))
      Ok(#(ctx4, ast.Use(lv, call_elab, body_elab)))
    }
    SLabeledFn(params, body) -> {
      // (fn* ((name default) ...) body) → (lam name (... (lam lastname body)))
      // Defaults are stored as surface metadata, compiled to regular curried lambdas.
      case params {
        [] -> elaborate_term(body, ctx)
        _ -> {
          let #(rev_params, ctx_with_bindings) =
            list.fold(params, #([], ctx), fn(acc, param) {
              let #(acc_params, c) = acc
              let #(name, _default) = param
              let #(c2, lv) = add_binding(c, name)
              #([lv, ..acc_params], c2)
            })
          let lvs = list.reverse(rev_params)
          use #(ctx_body, body_elab) <- result.try(
            elaborate_term(body, ctx_with_bindings),
          )
          let lam_wrapped =
            list.fold(lvs, body_elab, fn(acc, lv) { ast.Lambda(lv, acc) })
          Ok(#(ctx_body, lam_wrapped))
        }
      }
    }
  }
}

fn elaborate_case(
  sc: SCase,
  ctx: ElabCtx,
) -> Result(#(ElabCtx, ast.Case), ElaborateError) {
  let SCase(pattern: sp, guard: sg, body: sb) = sc
  use #(ctx2, pat) <- result.try(elaborate_pattern(sp, ctx))
  use #(ctx3, b) <- result.try(elaborate_term(sb, ctx2))
  let guard_elab = case sg {
    option.Some(g) -> {
      let #(_, g_term) = elaborate_term(g, ctx3) |> result.unwrap(#(ctx3, ast.Int(0)))
      option.Some(ast.GuardTerm(g_term))
    }
    option.None -> option.None
  }
  Ok(#(ctx3, ast.Case(pattern: pat, guard: guard_elab, body: b)))
}

fn elaborate_cases(
  cs: List(SCase),
  ctx: ElabCtx,
  acc: List(ast.Case),
) -> Result(#(ElabCtx, List(ast.Case)), ElaborateError) {
  case cs {
    [] -> Ok(#(ctx, list.reverse(acc)))
    [first, ..rest] -> {
      use #(ctx2, el) <- result.try(elaborate_case(first, ctx))
      let case_ctx =
        ElabCtx(..ctx2, bindings: ctx.bindings, next_local: ctx.next_local)
      elaborate_cases(rest, case_ctx, [el, ..acc])
    }
  }
}
