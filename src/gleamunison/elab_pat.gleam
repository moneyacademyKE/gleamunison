import gleam/dict
import gleam/list
import gleam/result
import gleamunison/ast
import gleamunison/elab_ctx.{type ElabCtx, add_binding}
import gleamunison/elab_types.{
  type ElaborateError, type SPattern, NameNotFound, SPAs, SPCons, SPConstructor,
  SPEmptyList, SPInt, SPText, SPVar,
}

pub fn elaborate_pattern(
  pat: SPattern,
  ctx: ElabCtx,
) -> Result(#(ElabCtx, ast.Pattern), ElaborateError) {
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
    SPConstructor(name, args) -> {
      use ctor_ref <- result.try(
        dict.get(ctx.names, name) |> result.replace_error(NameNotFound(name)),
      )
      case
        list.try_fold(args, #(ctx, []), fn(acc, arg) {
          let #(c_ctx, acc_args) = acc
          use #(n_ctx, pat) <- result.try(elaborate_pattern(arg, c_ctx))
          Ok(#(n_ctx, [pat, ..acc_args]))
        })
      {
        Ok(#(final_ctx, pats)) ->
          Ok(#(final_ctx, ast.PatConstructor(ctor_ref, list.reverse(pats))))
        Error(e) -> Error(e)
      }
    }
  }
}
