import gleam/list
import gleam/string
import gleamunison/identity.{type DefinitionRef, Ref}
import gleamunison/ast
import gleamunison/elaborate as elab
import gleamunison/elab_types.{type SurfaceTerm, type SurfaceDef, SurfaceUnit, SurfaceTermDef}
import gleamunison/compile.{module_name_for, compile_definition, new as new_compiler}
import gleamunison/types.{type TypeCache}

@external(erlang, "gleamunison_ffi", "string_to_binary")
pub fn string_to_binary(s: String) -> BitArray

@external(erlang, "gleamunison_ffi", "load_binary")
pub fn load_binary(mod_name: String, beam: BitArray) -> Result(Nil, String)

@external(erlang, "gleamunison_ffi", "unload_binary")
pub fn unload_binary(mod_name: String) -> Result(Nil, String)

@external(erlang, "gleamunison_repl_ffi", "eval_module")
pub fn eval_module(mod_name: String) -> Result(String, String)

pub fn ref_for_name(name: String) -> DefinitionRef {
  Ref(identity.hash_bytes(string_to_binary(name)))
}

pub fn do_eval(
  term: SurfaceTerm,
  name: String,
  cache: TypeCache,
  prev_defs: List(#(String, SurfaceDef)),
) -> Result(#(String, ast.Type, TypeCache), String) {
  let expr_ref = ref_for_name(name)
  let defs = [#(name, SurfaceTermDef(term)), ..prev_defs]
  case elab.elaborate_unit(SurfaceUnit(expr_ref, defs), cache) {
    Error(err) -> Error("Typecheck Error: " <> string.inspect(err))
    Ok(#(unit, next_cache)) -> {
      case list.key_find(unit.defs, expr_ref) {
        Error(_) -> Error("No def found")
        Ok(def) -> {
          let mod_name = module_name_for(expr_ref)
          let _ = unload_binary(mod_name)
          case compile_definition(new_compiler(), def, expr_ref) {
            Error(e) -> Error("Compile Error: " <> string.inspect(e))
            Ok(beam) -> case load_binary(mod_name, beam) {
              Error(err) -> Error("Load Error: " <> err)
              Ok(_) -> case eval_module(mod_name) {
                Error(err) -> Error("Runtime Error: " <> err)
                Ok(val_str) -> {
                  case def {
                    ast.TermDef(term: _, typ:) -> Ok(#(val_str, typ, next_cache))
                    _ -> Error("Expected term definition, but got type or ability declaration")
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

pub fn handle_define(
  name: String,
  val: SurfaceTerm,
  cache: TypeCache,
  prev_defs: List(#(String, SurfaceDef)),
) -> Result(#(TypeCache, List(#(String, SurfaceDef))), String) {
  let name_ref = ref_for_name(name)
  let prev_defs = list.filter(prev_defs, fn(pair) { pair.0 != name })
  let defs = [#(name, SurfaceTermDef(val)), ..prev_defs]
  case elab.elaborate_unit(SurfaceUnit(ref_for_name("repl_expr"), defs), cache) {
    Error(err) -> Error("Typecheck Error: " <> string.inspect(err))
    Ok(#(unit, next_cache)) -> {
      case list.key_find(unit.defs, name_ref) {
        Error(_) -> Error("No def found")
        Ok(def) -> {
          let mod_name = module_name_for(name_ref)
          let _ = unload_binary(mod_name)
          case compile_definition(new_compiler(), def, name_ref) {
            Error(e) -> Error("Compile Error: " <> string.inspect(e))
            Ok(beam) -> case load_binary(mod_name, beam) {
              Error(err) -> Error("Load Error: " <> err)
              Ok(_) -> Ok(#(next_cache, defs))
            }
          }
        }
      }
    }
  }
}

pub fn bootstrap_defs(
  defs: List(#(String, SurfaceDef)),
  cache: TypeCache,
) -> #(TypeCache, List(#(String, SurfaceDef))) {
  list.fold(defs, #(cache, []), fn(acc, pair) {
    let #(name, val_def) = pair
    let #(curr_cache, curr_defs) = acc
    case val_def {
      SurfaceTermDef(val) -> {
        case handle_define(name, val, curr_cache, curr_defs) {
          Ok(#(next_cache, next_defs)) -> #(next_cache, next_defs)
          Error(_) -> acc
        }
      }
      elab_types.SurfaceAbilityDef(_, _) -> {
        let name_ref = ref_for_name(name)
        case elab.elaborate_unit(SurfaceUnit(ref_for_name("repl_expr"), [#(name, val_def)]), curr_cache) {
          Error(_) -> acc
          Ok(#(unit, next_cache)) -> {
            case list.key_find(unit.defs, name_ref) {
              Error(_) -> acc
              Ok(def) -> {
                let mod_name = module_name_for(name_ref)
                let _ = unload_binary(mod_name)
                case compile_definition(new_compiler(), def, name_ref) {
                  Error(_) -> acc
                  Ok(beam) -> case load_binary(mod_name, beam) {
                    Error(_) -> acc
                    Ok(_) -> #(next_cache, [pair, ..curr_defs])
                  }
                }
              }
            }
          }
        }
      }
      _ -> acc
    }
  })
}
