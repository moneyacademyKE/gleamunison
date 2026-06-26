import gleam/dict
import gleam/list
import gleam/result
import gleamunison/ast
import gleamunison/identity.{Local}
import gleamunison/elab_types.{
  type SCase, type SurfaceTerm, type ElaborateError, SInt, SFloat, SText, SList, SVar, SRef, SApply, SLambda, SLet, SMatch, SDo, SHandle,
  UnknownOperation, MissingAbilityDecl, NameNotFound, SCase
}
import gleamunison/elab_ctx.{type ElabCtx, ElabCtx, add_binding, lookup_binding}
import gleamunison/elab_pat.{elaborate_pattern}

pub fn elaborate_term(term: SurfaceTerm, ctx: ElabCtx) -> Result(#(ElabCtx, ast.Term), ElaborateError) {
  case term {
    SInt(n) -> Ok(#(ctx, ast.Int(n)))
    SFloat(f) -> Ok(#(ctx, ast.Float(f)))
    SText(b) -> Ok(#(ctx, ast.Text(b)))
    SList(ts) -> {
      list.try_map(ts, fn(t) { elaborate_term(t, ctx) |> result.map(fn(p) { p.1 }) })
      |> result.map(fn(terms) { #(ctx, ast.List(terms)) })
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
      use ab_ref <- result.try(dict.get(ctx.abilities, ab) |> result.replace_error(MissingAbilityDecl(ab)))
      use terms <- result.try(list.try_map(args, fn(a) { elaborate_term(a, ctx) |> result.map(fn(p) { p.1 }) }))
      use op_idx <- result.try(dict.get(ctx.ops, #(ab, op)) |> result.replace_error(UnknownOperation(ab, op)))
      Ok(#(ctx, ast.Do(ab_ref, Local(op_idx), terms)))
    }
    SHandle(c, h, _) -> {
      use #(ctx2, comp) <- result.try(elaborate_term(c, ctx))
      use #(ctx3, hand) <- result.try(elaborate_term(h, ctx2))
      Ok(#(ctx3, ast.Handle(comp, hand)))
    }
  }
}

fn elaborate_case(sc: SCase, ctx: ElabCtx) -> Result(#(ElabCtx, ast.Case), ElaborateError) {
  let SCase(pattern: sp, body: sb) = sc
  use #(ctx2, pat) <- result.try(elaborate_pattern(sp, ctx))
  use #(ctx3, b) <- result.try(elaborate_term(sb, ctx2))
  Ok(#(ctx3, ast.Case(pattern: pat, body: b)))
}

fn elaborate_cases(cs: List(SCase), ctx: ElabCtx, acc: List(ast.Case)) -> Result(#(ElabCtx, List(ast.Case)), ElaborateError) {
  case cs {
    [] -> Ok(#(ctx, list.reverse(acc)))
    [first, ..rest] -> {
      use #(ctx2, el) <- result.try(elaborate_case(first, ctx))
      let case_ctx = ElabCtx(..ctx2, bindings: ctx.bindings)
      elaborate_cases(rest, case_ctx, [el, ..acc])
    }
  }
}
