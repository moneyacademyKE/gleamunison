import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import gleamunison/ast
import gleamunison/compile.{
  compile_definition, module_name_for, new as new_compiler,
}
import gleamunison/elab_types.{
  type SurfaceDef, type SurfaceTerm, SurfaceTermDef, SurfaceUnit,
}
import gleamunison/elaborate as elab
import gleamunison/genesis
import gleamunison/identity.{type DefinitionRef, Ref}
import gleamunison/types.{type TypeCache, CTTerm, TypeCache}

@external(erlang, "gleamunison_ffi", "string_to_binary")
pub fn string_to_binary(s: String) -> BitArray

@external(erlang, "gleamunison_ffi", "load_binary")
pub fn load_binary(mod_name: String, beam: BitArray) -> Result(Nil, String)

@external(erlang, "gleamunison_ffi", "unload_binary")
pub fn unload_binary(mod_name: String) -> Result(Nil, String)

@external(erlang, "gleamunison_repl_ffi", "eval_module")
pub fn eval_module(mod_name: String) -> Result(String, String)

@external(erlang, "gleamunison_ffi_io", "serialize_term")
pub fn serialize_term(term: a) -> BitArray

@external(erlang, "gleamunison_ffi_io", "deserialize_term")
pub fn deserialize_term(bytes: BitArray) -> a

fn lev_dist_limit(s: List(String), t: List(String), limit: Int) -> Int {
  case limit < 0 {
    True -> 3
    False -> {
      case s, t {
        [], _ -> {
          let len = list.length(t)
          case len <= limit {
            True -> len
            False -> 3
          }
        }
        _, [] -> {
          let len = list.length(s)
          case len <= limit {
            True -> len
            False -> 3
          }
        }
        [x, ..xs], [y, ..ys] -> {
          case x == y {
            True -> lev_dist_limit(xs, ys, limit)
            False -> {
              let d1 = lev_dist_limit(xs, t, limit - 1) + 1
              let d2 = lev_dist_limit(s, ys, limit - 1) + 1
              let d3 = lev_dist_limit(xs, ys, limit - 1) + 1
              int.min(d1, int.min(d2, d3))
            }
          }
        }
      }
    }
  }
}

fn find_suggestions(
  name: String,
  prev_defs: List(#(String, SurfaceDef)),
) -> List(String) {
  let name_chars = string.to_graphemes(name)
  list.filter_map(prev_defs, fn(pair) {
    let #(def_name, _) = pair
    let def_chars = string.to_graphemes(def_name)
    let dist = lev_dist_limit(name_chars, def_chars, 2)
    case dist <= 2 {
      True -> Ok(def_name)
      False -> Error(Nil)
    }
  })
}

/// Render an elaboration error for humans. Public: the LSP server renders
/// the same messages, but needs the span separately (see span_of_error).
pub fn format_elab_error(
  err: elab_types.ElaborateError,
  prev_defs: List(#(String, SurfaceDef)),
) -> String {
  case err {
    elab_types.NameNotFound(name) -> {
      let suggestions = find_suggestions(name, prev_defs)
      case suggestions {
        [] ->
          "[E001] undefined variable `"
          <> name
          <> "`. Define it with (define "
          <> name
          <> " <expr>)."
        _ ->
          "[E001] undefined variable `"
          <> name
          <> "`. Did you mean: "
          <> string.join(suggestions, ", ")
          <> "? Define it with (define "
          <> name
          <> " <expr>)."
      }
    }
    elab_types.UnknownOperation(ab, op) ->
      "[E002] unknown operation `"
      <> op
      <> "` in ability `"
      <> ab
      <> "`. Check the ability declaration for available operations."
    elab_types.MissingAbilityDecl(ab) ->
      "[E003] undefined ability `"
      <> ab
      <> "`. Declare it with (ability "
      <> ab
      <> " (op1 args ret) ...)."
    elab_types.InferFailed(msg) ->
      "[E004] type error: "
      <> msg
      <> ". The expression could not be type-checked."
    elab_types.UnsupportedTypeRef(desc) ->
      "[E005] unsupported type reference: " <> desc <> "."
    elab_types.At(inner, span) ->
      format_elab_error(inner, prev_defs)
      <> " (at line "
      <> int.to_string(span.line)
      <> ", col "
      <> int.to_string(span.col)
      <> ")"
  }
}

pub fn ref_for_name(name: String) -> DefinitionRef {
  Ref(identity.hash_bytes(string_to_binary(name)))
}

/// Elaborate + compile + load a term definition, returning the loaded
/// module name, its type, and the advanced cache. Split from do_eval so
/// callers can choose how to run the module: plainly (REPL), or wrapped
/// in handler frames (replay, capabilities, transcripts).
pub fn compile_def_module(
  term: SurfaceTerm,
  name: String,
  cache: TypeCache,
  prev_defs: List(#(String, SurfaceDef)),
) -> Result(#(String, ast.Type, TypeCache), String) {
  let expr_ref = ref_for_name(name)
  let defs = [#(name, SurfaceTermDef(term)), ..prev_defs]
  case elab.elaborate_unit(SurfaceUnit(expr_ref, defs), cache) {
    Error(err) ->
      Error("Typecheck Error: " <> format_elab_error(err, prev_defs))
    Ok(#(unit, next_cache, _elab_ctx)) -> {
      case list.key_find(unit.defs, expr_ref) {
        Error(_) -> Error("No def found")
        Ok(def) -> {
          let mod_name = module_name_for(expr_ref)
          let _ = unload_binary(mod_name)
          case compile_definition(new_compiler(), def, expr_ref) {
            Error(e) -> Error("Compile Error: " <> string.inspect(e))
            Ok(beam) ->
              case load_binary(mod_name, beam) {
                Error(err) -> Error("Load Error: " <> err)
                Ok(_) ->
                  case def {
                    ast.TermDef(term: _, typ:) ->
                      Ok(#(mod_name, typ, next_cache))
                    _ ->
                      Error(
                        "Expected term definition, but got type or ability declaration",
                      )
                  }
              }
          }
        }
      }
    }
  }
}

pub fn do_eval(
  term: SurfaceTerm,
  name: String,
  cache: TypeCache,
  prev_defs: List(#(String, SurfaceDef)),
) -> Result(#(String, ast.Type, TypeCache), String) {
  case compile_def_module(term, name, cache, prev_defs) {
    Error(err) -> Error(err)
    Ok(#(mod_name, typ, next_cache)) ->
      case eval_module(mod_name) {
        Error(err) -> Error("Runtime Error: " <> err)
        Ok(val_str) -> Ok(#(val_str, typ, next_cache))
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
  // Seed builtin terms with their declared op types BEFORE elaboration, so
  // `RefTo(genesis_ref)` infers the real type instead of TypeVar(-1).
  // Names match the Math ability ops by convention; Show/Remote ops keep
  // their type variables (polymorphic is honest there).
  let cache = seed_builtin_term_types(cache)
  let prev_defs = list.filter(prev_defs, fn(pair) { pair.0 != name })
  let defs = [#(name, SurfaceTermDef(val)), ..prev_defs]
  case
    elab.elaborate_unit(SurfaceUnit(ref_for_name("repl_expr"), defs), cache)
  {
    Error(err) ->
      Error("Typecheck Error: " <> format_elab_error(err, prev_defs))
    Ok(#(unit, next_cache, _elab_ctx)) -> {
      case list.key_find(unit.defs, name_ref) {
        Error(_) -> Error("No def found")
        Ok(def) -> {
          let mod_name = module_name_for(name_ref)
          let _ = unload_binary(mod_name)
          case compile_definition(new_compiler(), def, name_ref) {
            Error(e) -> Error("Compile Error: " <> string.inspect(e))
            Ok(beam) ->
              case load_binary(mod_name, beam) {
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
          Error(err) -> {
            io.println("Bootstrap error for " <> name <> ": " <> err)
            acc
          }
        }
      }
      elab_types.SurfaceAbilityDef(_, _) -> {
        let name_ref = ref_for_name(name)
        case
          elab.elaborate_unit(
            SurfaceUnit(ref_for_name("repl_expr"), [#(name, val_def)]),
            curr_cache,
          )
        {
          Error(_) -> acc
          Ok(#(unit, next_cache, _elab_ctx)) -> {
            case list.key_find(unit.defs, name_ref) {
              Error(_) -> acc
              Ok(def) -> {
                let mod_name = module_name_for(name_ref)
                let _ = unload_binary(mod_name)
                case compile_definition(new_compiler(), def, name_ref) {
                  Error(_) -> acc
                  Ok(beam) ->
                    case load_binary(mod_name, beam) {
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

/// Bootstrap terms (add, sub, mul, ...) dual-register as Math ability ops
/// whose signatures carry the real types. Elaborating a term as SRef to a
/// genesis ref would otherwise cache TypeVar(-1), leaving the checker blind
/// to builtin misuse. Seed the genesis refs with the declared op types so
/// every RefTo resolves honestly. This is a pure data move: the op table is
/// the source of truth, the cache just stops dropping it.
fn seed_builtin_term_types(cache: TypeCache) -> TypeCache {
  let seeds = [
    #(genesis.builtin_int_add(), int_int_int()),
    #(genesis.builtin_sub(), int_int_int()),
    #(genesis.builtin_mul(), int_int_int()),
  ]
  list.fold(seeds, cache, fn(acc, pair) {
    TypeCache(dict.insert(acc.entries, pair.0, CTTerm(pair.1)))
  })
}

fn int_int_int() -> ast.Type {
  let int = ast.Builtin(ast.IntType)
  ast.Fn([int, int], int, ast.Required([]))
}
