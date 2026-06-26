import gleam/dict
import gleam/list
import gleam/string
import gleamunison/identity.{Ref, hash_to_debug_string}
import gleamunison/ast
import gleamunison/types.{type TypeCache, CTTerm}
import gleamunison/inference.{infer_term}
import gleamunison/elab_types.{type ElaborateError, InferFailed}
import gleamunison/infer_helper.{normalize_type}

pub fn typecheck_unit(unit: ast.Unit, cache: TypeCache) -> Result(#(ast.Unit, TypeCache), ElaborateError) {
  let ast.Unit(root: _, defs:) = unit
  case list.try_fold(defs, cache, fn(current_cache, kv) {
    let #(ref, def) = kv
    case def {
      ast.TermDef(term:, typ:) -> {
        case infer_term(term, current_cache) {
          Ok(inferred) -> {
            case normalize_type(inferred) == normalize_type(typ) {
              True -> {
                let next_cache = types.TypeCache(dict.insert(current_cache.entries, ref, CTTerm(typ)))
                Ok(next_cache)
              }
              False -> {
                let Ref(h) = ref
                Error(InferFailed("Type mismatch for " <> hash_to_debug_string(h)))
              }
            }
          }
          Error(e) -> Error(InferFailed(string.inspect(e)))
        }
      }
      _ -> Ok(current_cache)
    }
  }) {
    Ok(final_cache) -> Ok(#(unit, final_cache))
    Error(e) -> Error(e)
  }
}
