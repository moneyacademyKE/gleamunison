import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleamunison/identity.{type DefinitionRef, Local}
import gleamunison/ast
import gleamunison/types.{type TypeCache, TypeCache, CTTerm, CTType, CTAbility}
import gleamunison/inference.{infer_term}
import gleamunison/elab_types.{
  type SurfaceTerm, type Typ, type SurfaceOp, type ElaborateError,
  InferFailed
}
import gleamunison/elab_ctx.{type ElabCtx}
import gleamunison/elab_term.{elaborate_term}
import gleamunison/lower.{lower_type_ref, type_ref_to_type}

pub fn elab_term_def(
  st: SurfaceTerm,
  ctx: ElabCtx,
  ref: DefinitionRef,
  cache: TypeCache,
) -> Result(#(ast.Definition, TypeCache), ElaborateError) {
  case elaborate_term(st, ctx) {
    Ok(#(_, term)) -> {
      case infer_term(term, cache) {
        Ok(typ) -> {
          let next_cache = TypeCache(dict_insert(cache.entries, ref, CTTerm(typ)))
          Ok(#(ast.TermDef(term:, typ:), next_cache))
        }
        Error(e) -> Error(InferFailed(string.inspect(e)))
      }
    }
    Error(e) -> Error(e)
  }
}

pub fn elab_type_def(
  t: Typ,
  ref: DefinitionRef,
  cache: TypeCache,
) -> Result(#(ast.Definition, TypeCache), ElaborateError) {
  case lower_type_ref(t) {
    Ok(tr) -> {
      let type_decl = ast.Structural(Local(0), [], [ast.Constructor(Local(1), [tr])])
      let next_cache = TypeCache(dict_insert(cache.entries, ref, CTType))
      Ok(#(ast.TypeDef(type_decl), next_cache))
    }
    Error(e) -> Error(e)
  }
}

pub fn elab_ability_def(
  ops: List(SurfaceOp),
  ref: DefinitionRef,
  cache: TypeCache,
) -> Result(#(ast.Definition, TypeCache), ElaborateError) {
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
      let next_cache = TypeCache(dict_insert(cache.entries, ref, CTAbility(op_typs)))
      let ability_decl = ast.AbilityDecl(ast.AbilityDeclaration(Local(0), aops))
      Ok(#(ability_decl, next_cache))
    }
    Error(e) -> Error(e)
  }
}

// Helper to avoid importing gleam/dict directly if not needed, or we can just import it.
import gleam/dict
fn dict_insert(d: dict.Dict(k, v), k: k, v: v) -> dict.Dict(k, v) {
  dict.insert(d, k, v)
}
