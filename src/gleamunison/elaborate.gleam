import gleam/dict
import gleam/list
import gleamunison/ast
import gleamunison/elab_ctx.{type ElabCtx, ElabCtx, empty_elab_ctx}
import gleamunison/elab_def
import gleamunison/elab_types.{
  type ElaborateError, type SurfaceDef, type SurfaceUnit, InferFailed,
  SurfaceAbilityDef, SurfacePubTypeAlias, SurfaceTermDef, SurfaceTypeAlias,
  SurfaceTypeDef, SurfaceUnit,
}
import gleamunison/identity.{type DefinitionRef, Local, Ref}
import gleamunison/typecheck
import gleamunison/types.{type TypeCache, CTType, TypeCache}

@external(erlang, "gleamunison_ffi", "string_to_binary")
fn string_to_binary(_s: String) -> BitArray

fn ref_for_name(name: String) -> DefinitionRef {
  Ref(identity.hash_bytes(string_to_binary(name)))
}

fn register_ability_ops(
  ctx: ElabCtx,
  _name: String,
  sd: SurfaceDef,
  ref: DefinitionRef,
) -> ElabCtx {
  case sd {
    SurfaceAbilityDef(ab_name, ops) -> {
      let ctx2 =
        ElabCtx(..ctx, abilities: dict.insert(ctx.abilities, ab_name, ref))
      list.index_fold(ops, ctx2, fn(acc, op, idx) {
        ElabCtx(..acc, ops: dict.insert(acc.ops, #(ab_name, op.name), idx))
      })
    }
    _ -> ctx
  }
}

pub fn elaborate_unit(
  su: SurfaceUnit,
  cache: TypeCache,
) -> Result(#(ast.Unit, TypeCache, ElabCtx), ElaborateError) {
  let SurfaceUnit(root: r, defs: ds) = su
  let ctx = case ds {
    [] -> empty_elab_ctx()
    [#(first_name, first_def), ..rest] -> {
      let first_ref = ref_for_name(first_name)
      let acc =
        register_ability_ops(empty_elab_ctx(), first_name, first_def, first_ref)
      let acc2 =
        ElabCtx(..acc, names: dict.insert(acc.names, first_name, first_ref))
      list.fold(rest, acc2, fn(acc3, kv) {
        let #(name, sd) = kv
        let ref = ref_for_name(name)
        let acc4 = register_ability_ops(acc3, name, sd, ref)
        ElabCtx(..acc4, names: dict.insert(acc4.names, name, ref))
      })
    }
  }

  let folded =
    list.fold_until(ds, Ok(#([], cache)), fn(acc_res, kv) {
      case acc_res {
        Error(e) -> list.Stop(Error(e))
        Ok(#(acc_defs, current_cache)) -> {
          let #(name, sd) = kv
          case dict.get(ctx.names, name) {
            Error(_) ->
              list.Stop(
                Error(InferFailed("internal: ref not found for " <> name)),
              )
            Ok(ref) -> {
              let res = case sd {
                SurfaceTermDef(st) ->
                  elab_def.elab_term_def(st, ctx, ref, current_cache)
                SurfaceTypeDef(t) ->
                  elab_def.elab_type_def(t, ref, current_cache)
                SurfaceAbilityDef(_, ops) ->
                  elab_def.elab_ability_def(ops, ref, current_cache)
                SurfaceTypeAlias(_, _) | SurfacePubTypeAlias(_, _) -> {
                  let next_cache =
                    TypeCache(dict.insert(current_cache.entries, ref, CTType))
                  Ok(#(
                    ast.TypeDef(ast.Structural(Local(0), [], [])),
                    next_cache,
                  ))
                }
              }
              case res {
                Ok(#(def, next_cache)) ->
                  list.Continue(Ok(#([#(ref, def), ..acc_defs], next_cache)))
                Error(e) -> list.Stop(Error(e))
              }
            }
          }
        }
      }
    })

  case folded {
    Ok(#(defs, next_cache)) ->
      Ok(#(ast.Unit(r, list.reverse(defs)), next_cache, ctx))
    Error(e) -> Error(e)
  }
}

pub fn typecheck_unit(
  unit: ast.Unit,
  cache: TypeCache,
) -> Result(#(ast.Unit, TypeCache), ElaborateError) {
  typecheck.typecheck_unit(unit, cache)
}
