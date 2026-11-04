import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import gleamunison/ast
import gleamunison/bootstraps
import gleamunison/compile.{compile_definition, module_name_for}
import gleamunison/elab_types.{
  type SurfaceDef, type SurfaceTerm, SurfaceTermDef, SurfaceUnit,
}
import gleamunison/elaborate as elab
import gleamunison/identity.{type DefinitionRef}
import gleamunison/loader_ffi.{eval_module, load_binary, unload_binary}
import gleamunison/types.{type TypeCache, CTTerm, TypeCache}

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

/// The name-to-ref derivation belongs to identity; this is the public
/// contract its callers have always used, kept as a delegate rather than
/// left as a second authority for the bytes.
pub fn ref_for_name(name: String) -> DefinitionRef {
  identity.name_ref(name)
}

/// Elaborate + compile + load a term definition, returning the loaded
/// module name, its type, and the advanced cache. Split from do_eval so
/// callers can choose how to run the module: plainly (REPL), or wrapped
/// in handler frames (replay, capabilities, transcripts).
fn compile_def_module(
  term: SurfaceTerm,
  name: String,
  cache: TypeCache,
  prev_defs: List(#(String, SurfaceDef)),
) -> Result(#(String, ast.Type, TypeCache), String) {
  let expr_ref = ref_for_name(name)
  let defs = [#(name, SurfaceTermDef(term)), ..prev_defs]
  case elaborate_keyed_unit(expr_ref, expr_ref, defs, cache, prev_defs) {
    Error(err) -> Error(err)
    Ok(#(def, next_cache)) -> {
      let mod_name = module_name_for(expr_ref)
      case compile_and_load(mod_name, def, expr_ref) {
        Error(err) -> Error(err)
        Ok(_) ->
          case def {
            ast.TermDef(term: _, typ:) -> Ok(#(mod_name, typ, next_cache))
            _ ->
              Error(
                "Expected term definition, but got type or ability declaration",
              )
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
    elaborate_keyed_unit(
      ref_for_name("repl_expr"),
      name_ref,
      defs,
      cache,
      prev_defs,
    )
  {
    Error(err) -> Error(err)
    Ok(#(def, next_cache)) -> {
      let mod_name = module_name_for(name_ref)
      case compile_and_load(mod_name, def, name_ref) {
        Error(err) -> Error(err)
        Ok(_) -> Ok(#(next_cache, defs))
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
          elaborate_keyed_unit(
            ref_for_name("repl_expr"),
            name_ref,
            [#(name, val_def)],
            curr_cache,
            curr_defs,
          )
        {
          Error(_) -> acc
          Ok(#(def, next_cache)) -> {
            let mod_name = module_name_for(name_ref)
            case compile_and_load(mod_name, def, name_ref) {
              Error(_) -> acc
              Ok(_) -> #(next_cache, [pair, ..curr_defs])
            }
          }
        }
      }
      _ -> acc
    }
  })
}

/// Elaborate a unit and key-find one definition by ref. One owner for the
/// prologue every define-path in this module repeats: elaborate under a
/// `unit_ref` (a scratch name — historically "repl_expr" — that names the
/// elaboration unit, never a def), then look up the def the caller
/// actually wants by its own `lookup_ref`. The `prev_defs` passed here is
/// used only for error *rendering* (suggestions), never for elaboration —
/// the `defs` list is the truth.
fn elaborate_keyed_unit(
  unit_ref: DefinitionRef,
  lookup_ref: DefinitionRef,
  defs: List(#(String, SurfaceDef)),
  cache: TypeCache,
  prev_defs: List(#(String, SurfaceDef)),
) -> Result(#(ast.Definition, TypeCache), String) {
  case elab.elaborate_unit(SurfaceUnit(unit_ref, defs), cache) {
    Error(err) ->
      Error("Typecheck Error: " <> format_elab_error(err, prev_defs))
    Ok(#(unit, next_cache, _elab_ctx)) ->
      case list.key_find(unit.defs, lookup_ref) {
        Error(_) -> Error("No def found")
        Ok(def) -> Ok(#(def, next_cache))
      }
  }
}

/// Unload any stale beam, compile the def, load the result. One owner for
/// the stateless reload chain. loader.gleam's compile_and_load is a
/// different authority: it carries Loader LRU/purge state for the store
/// domain. Error strings are the historical contract of every caller.
fn compile_and_load(
  mod_name: String,
  def: ast.Definition,
  ref: DefinitionRef,
) -> Result(Nil, String) {
  let _ = unload_binary(mod_name)
  case compile_definition(def, ref) {
    Error(e) -> {
      let compile.InternalError(reason) = e
      Error("Compile Error: " <> reason)
    }
    Ok(beam) ->
      case load_binary(mod_name, beam) {
        Error(err) -> Error("Load Error: " <> err)
        Ok(_) -> Ok(Nil)
      }
  }
}

/// Every builtin signature comes from the bootstrap table. A partial seed
/// here used to leave all but three builtins with the unknown TypeVar(-1).
pub fn seed_builtin_term_types(cache: TypeCache) -> TypeCache {
  list.fold(bootstraps.get_init_defs_data(), cache, fn(acc, definition) {
    case definition {
      bootstraps.BTerm(_, ref, typ) ->
        TypeCache(dict.insert(acc.entries, ref, CTTerm(typ)))
      bootstraps.BAbility(_, _) -> acc
    }
  })
}
