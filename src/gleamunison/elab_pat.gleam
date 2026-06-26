import gleamunison/ast
import gleamunison/elab_types.{type SPattern, type ElaborateError, SPVar, SPInt, SPText, SPCons, SPEmptyList, SPAs}
import gleamunison/elab_ctx.{type ElabCtx, add_binding}

pub fn elaborate_pattern(pat: SPattern, ctx: ElabCtx) -> Result(#(ElabCtx, ast.Pattern), ElaborateError) {
  case pat {
    SPVar(name) -> {
      let #(ctx2, lv) = add_binding(ctx, name)
      Ok(#(ctx2, ast.PatVar(lv)))
    }
    SPInt(n) -> Ok(#(ctx, ast.PatInt(n)))
    SPText(b) -> Ok(#(ctx, ast.PatText(b)))
    SPCons(head: h, tail: t) -> {
      let #(ctx2, hv) = add_binding(ctx, h)
      let #(ctx3, tv) = add_binding(ctx2, t)
      Ok(#(ctx3, ast.PatCons(hv, tv)))
    }
    SPEmptyList -> Ok(#(ctx, ast.PatEmptyList))
    SPAs(name: n, inner: i) -> {
      let #(ctx2, lv) = add_binding(ctx, n)
      case elaborate_pattern(i, ctx2) {
        Ok(#(ctx3, ip)) -> Ok(#(ctx3, ast.PatAs(lv, ip)))
        Error(e) -> Error(e)
      }
    }
  }
}
