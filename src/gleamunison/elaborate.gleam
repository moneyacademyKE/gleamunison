import gleam/dict
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleamunison/identity.{type DefinitionRef, Local, Ref}
import gleamunison/ast as ast
import gleamunison/types.{type TypeCache, CTTerm, CTType, CTAbility}
import gleamunison/inference.{infer_term}
import gleamunison/elab_types.{
  type SurfaceUnit, type ElaborateError, type SurfaceDef, SurfaceUnit, SurfaceTermDef, SurfaceTypeDef, SurfaceAbilityDef,
  InferFailed
}
import gleamunison/elab_ctx.{type ElabCtx, ElabCtx, empty_elab_ctx}
import gleamunison/elab_term.{elaborate_term}
import gleamunison/lower.{lower_type_ref, type_ref_to_type}
import gleamunison/typecheck

@external(erlang, "gleamunison_ffi", "string_to_binary")
fn string_to_binary(_s: String) -> BitArray

fn ref_for_name(name: String) -> DefinitionRef {
  Ref(identity.hash_bytes(string_to_binary(name)))
}

fn register_ability_ops(ctx: ElabCtx, _name: String, sd: SurfaceDef, ref: DefinitionRef) -> ElabCtx {
  case sd {
    SurfaceAbilityDef(ab_name, ops) -> {
      let ctx2 = ElabCtx(..ctx, abilities: dict.insert(ctx.abilities, ab_name, ref))
      list.index_fold(ops, ctx2, fn(acc, op, idx) {
        ElabCtx(..acc, ops: dict.insert(acc.ops, #(ab_name, op.name), idx))
      })
    }
    _ -> ctx
  }
}

pub fn elaborate_unit(su: SurfaceUnit, cache: TypeCache) -> Result(#(ast.Unit, TypeCache), ElaborateError) {
  let SurfaceUnit(root: r, defs: ds) = su
  let ctx = case ds {
    [] -> empty_elab_ctx()
    [#(first_name, first_def), ..rest] -> {
      let first_ref = ref_for_name(first_name)
      let acc = register_ability_ops(empty_elab_ctx(), first_name, first_def, first_ref)
      let acc2 = ElabCtx(..acc, names: dict.insert(acc.names, first_name, first_ref))
      list.fold(rest, acc2, fn(acc3, kv) {
        let #(name, sd) = kv
        let ref = ref_for_name(name)
        let acc4 = register_ability_ops(acc3, name, sd, ref)
        ElabCtx(..acc4, names: dict.insert(acc4.names, name, ref))
      })
    }
  }

  let folded = list.fold_until(ds, Ok(#([], cache)), fn(acc_res, kv) {
    case acc_res {
      Error(e) -> list.Stop(Error(e))
      Ok(#(acc_defs, current_cache)) -> {
        let #(name, sd) = kv
        let ref = case dict.get(ctx.names, name) {
          Ok(ref_found) -> ref_found
          _ -> r
        }
        case sd {
          SurfaceTermDef(st) -> {
            case elaborate_term(st, ctx) {
              Ok(#(_, term)) -> {
                case infer_term(term, current_cache) {
                  Ok(typ) -> {
                    let next_cache = types.TypeCache(dict.insert(current_cache.entries, ref, CTTerm(typ)))
                    list.Continue(Ok(#([#(ref, ast.TermDef(term:, typ:)), ..acc_defs], next_cache)))
                  }
                  Error(e) -> list.Stop(Error(InferFailed(string.inspect(e))))
                }
              }
              Error(e) -> list.Stop(Error(e))
            }
          }
          SurfaceTypeDef(t) -> {
            case lower_type_ref(t) {
              Ok(tr) -> {
                let type_decl = ast.Structural(Local(0), [], [ast.Constructor(Local(0), [tr])])
                let next_cache = types.TypeCache(dict.insert(current_cache.entries, ref, CTType))
                list.Continue(Ok(#([#(ref, ast.TypeDef(type_decl)), ..acc_defs], next_cache)))
              }
              Error(e) -> list.Stop(Error(e))
            }
          }
          SurfaceAbilityDef(_, ops) -> {
            case list.try_map(ops, fn(op) {
              use ins <- result.try(list.try_map(op.inputs, lower_type_ref))
              use out <- result.try(lower_type_ref(op.output))
              Ok(#(op.name, ins, out))
            }) {
              Ok(lowered_ops) -> {
                let aops = list.map(lowered_ops, fn(lo) {
                  ast.Operation(Local(0), lo.1, lo.2)
                })
                let op_typs = list.map(lowered_ops, fn(lo) {
                  let inputs = list.map(lo.1, type_ref_to_type)
                  let output = type_ref_to_type(lo.2)
                  types.OperationType(name: option.Some(lo.0), inputs:, output:)
                })
                let next_cache = types.TypeCache(dict.insert(current_cache.entries, ref, CTAbility(op_typs)))
                let ability_decl = ast.AbilityDecl(ast.AbilityDeclaration(Local(0), aops))
                list.Continue(Ok(#([#(ref, ability_decl), ..acc_defs], next_cache)))
              }
              Error(e) -> list.Stop(Error(e))
            }
          }
        }
      }
    }
  })

  case folded {
    Ok(#(defs, next_cache)) -> Ok(#(ast.Unit(r, list.reverse(defs)), next_cache))
    Error(e) -> Error(e)
  }
}

pub fn typecheck_unit(unit: ast.Unit, cache: TypeCache) -> Result(#(ast.Unit, TypeCache), ElaborateError) {
  typecheck.typecheck_unit(unit, cache)
}
