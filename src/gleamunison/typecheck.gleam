import gleam/dict
import gleam/list
import gleam/string
import gleamunison/identity.{Ref, hash_to_debug_string}
import gleamunison/ast
import gleamunison/types.{type TypeCache, CTTerm}
import gleamunison/inference.{infer_term}
import gleamunison/elab_types.{type ElaborateError, InferFailed}

fn normalize_type(t: ast.Type) -> ast.Type {
  normalize_type_state(t, dict.new(), 0).0
}

fn normalize_type_state(
  t: ast.Type,
  m: dict.Dict(Int, Int),
  next: Int,
) -> #(ast.Type, dict.Dict(Int, Int), Int) {
  case t {
    ast.TypeVar(i) -> {
      case dict.get(m, i) {
        Ok(new_i) -> #(ast.TypeVar(new_i), m, next)
        Error(_) -> #(ast.TypeVar(next), dict.insert(m, i, next), next + 1)
      }
    }
    ast.AbilityVar(i) -> #(ast.AbilityVar(i), m, next)
    ast.Fn(params, result, requires) -> {
      let #(params2, m2, next2) =
        list.fold(params, #([], m, next), fn(acc, p) {
          let #(acc_params, acc_m, acc_next) = acc
          let #(p2, new_m, new_next) = normalize_type_state(p, acc_m, acc_next)
          #([p2, ..acc_params], new_m, new_next)
        })
      let params2 = list.reverse(params2)
      let #(result2, m3, next3) = normalize_type_state(result, m2, next2)
      #(ast.Fn(params2, result2, requires), m3, next3)
    }
    ast.App(name, args) -> {
      let #(args2, m2, next2) =
        list.fold(args, #([], m, next), fn(acc, a) {
          let #(acc_args, acc_m, acc_next) = acc
          let #(a2, new_m, new_next) = normalize_type_state(a, acc_m, acc_next)
          #([a2, ..acc_args], new_m, new_next)
        })
      let args2 = list.reverse(args2)
      #(ast.App(name, args2), m2, next2)
    }
    ast.Builtin(_) -> #(t, m, next)
  }
}

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
