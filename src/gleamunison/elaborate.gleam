import gleam/dict
import gleam/list
import gleamunison/identity.{type DefinitionRef, Local, Ref}
import gleamunison/ast as ast
import gleamunison/types.{type TypeCache}
import gleamunison/inference.{infer_term}
import gleamunison/elab_types.{
  type SurfaceUnit, type ElaborateError, type SurfaceDef, type Typ, SurfaceUnit, SurfaceTermDef, SurfaceTypeDef, SurfaceAbilityDef, TVar, TCon
}
import gleamunison/elab_ctx.{type ElabCtx, ElabCtx, empty_elab_ctx}
import gleamunison/elab_term.{elaborate_term}

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
      let acc = register_ability_ops(empty_elab_ctx(), first_name, first_def, r)
      let acc2 = ElabCtx(..acc, names: dict.insert(acc.names, first_name, r))
      list.fold(rest, acc2, fn(acc3, kv) {
        let #(name, sd) = kv
        let ref = ref_for_name(name)
        let acc4 = register_ability_ops(acc3, name, sd, ref)
        ElabCtx(..acc4, names: dict.insert(acc4.names, name, ref))
      })
    }
  }

  case list.try_map(ds, fn(kv) {
    let #(name, sd) = kv
    let ref = case dict.get(ctx.names, name) {
      Ok(ref_found) -> ref_found
      _ -> r
    }
    case sd {
      SurfaceTermDef(st) -> {
        case elaborate_term(st, ctx) {
          Ok(#(_, term)) -> {
            case infer_term(term, cache) {
              Ok(typ) -> Ok(#(ref, ast.TermDef(term:, typ:)))
              Error(_) -> Ok(#(ref, ast.TermDef(term:, typ: ast.Builtin(ast.IntType))))
            }
          }
          Error(e) -> Error(e)
        }
      }
      SurfaceTypeDef(t) -> {
        let type_decl = ast.Structural(Local(0), [], [ast.Constructor(Local(0), [lower_type_ref(t)])])
        Ok(#(ref, ast.TypeDef(type_decl)))
      }
      SurfaceAbilityDef(_ab_name, ops) -> {
        let aops = list.map(ops, fn(op) {
          ast.Operation(Local(0), list.map(op.inputs, lower_type_ref), lower_type_ref(op.output))
        })
        Ok(#(ref, ast.AbilityDecl(ast.AbilityDeclaration(Local(0), aops))))
      }
    }
  }) {
    Ok(defs) -> Ok(#(ast.Unit(r, defs), cache))
    Error(e) -> Error(e)
  }
}

fn lower_type_ref(t: Typ) -> ast.TypeRef {
  case t {
    TVar(_) -> ast.TypeRefVar(Local(0))
    TCon(r) -> ast.TypeCon(r)
    _ -> ast.TypeCon(Ref(identity.hash_bytes(<<>>)))
  }
}

pub fn typecheck_unit(unit: ast.Unit, cache: TypeCache) -> Result(#(ast.Unit, TypeCache), ElaborateError) {
  Ok(#(unit, cache))
}
