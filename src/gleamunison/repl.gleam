import gleam/io
import gleam/string
import gleam/list
import gleam/int
import gleam/result
import gleamunison/identity.{type DefinitionRef, Ref, builtin_int_add, builtin_io_read_line,
  builtin_process_spawn, builtin_process_self, builtin_process_send, builtin_process_recv,
  builtin_timer_sleep, builtin_timer_now,
  builtin_sub, builtin_mul, builtin_div, builtin_mod,
  builtin_eq, builtin_lt, builtin_gt,
  builtin_and, builtin_or, builtin_not,
  builtin_string_concat, builtin_string_length, builtin_string_contains,
  builtin_string_slice, builtin_string_upcase, builtin_string_downcase,
  builtin_string_replace, builtin_string_split, builtin_string_trim, builtin_string_to_int,
  builtin_list_length, builtin_list_reverse, builtin_list_map, builtin_list_filter,
  builtin_list_fold, builtin_list_append, builtin_list_flatten, builtin_list_member,
  builtin_list_range, builtin_list_sort,
  builtin_pair, builtin_fst, builtin_snd,
  builtin_left, builtin_right,
  builtin_dict_new, builtin_dict_get, builtin_dict_set,
  builtin_set_new, builtin_set_insert}
import gleamunison/ast
import gleamunison/parser
import gleamunison/elaborate as elab
import gleamunison/elab_types.{SurfaceUnit, SurfaceTermDef}
import gleamunison/codebase.{insert, hash_of_definition}
import gleamunison/compile.{module_name_for, compile_definition, new as new_compiler}
import gleamunison/loader.{ensure_loaded}
import gleamunison/types.{empty_cache}

@external(erlang, "gleamunison_ffi", "string_to_binary")
fn string_to_binary(s: String) -> BitArray

@external(erlang, "gleamunison_ffi", "load_binary")
fn load_binary(mod_name: String, beam: BitArray) -> Result(Nil, String)

@external(erlang, "gleamunison_ffi", "unload_binary")
fn unload_binary(mod_name: String) -> Result(Nil, String)

@external(erlang, "gleamunison_repl_ffi", "eval_module")
fn eval_module(mod_name: String) -> Result(String, String)

@external(erlang, "gleamunison_repl_ffi", "read_line")
fn read_line(prompt: String) -> Result(String, Nil)

fn ref_for_name(name: String) -> DefinitionRef {
  Ref(identity.hash_bytes(string_to_binary(name)))
}

/// Evaluate a gleamunison expression string and return the result as a string.
/// Used by the HTTP server's /eval endpoint.
pub fn eval_string(expr: String) -> Result(String, String) {
  case parser.parse_string(expr) {
    Error(e) -> Error("Parse Error: " <> e.message)
    Ok(elab_types.SList([elab_types.SVar("define"), elab_types.SVar(name), _val])) ->
      Error("Define not supported in eval endpoint: " <> name)
    Ok(term) -> {
      let expr_ref = ref_for_name("repl_expr")
      let defs = [#("repl_expr", SurfaceTermDef(term))]
      let cache = empty_cache()
      case elab.elaborate_unit(SurfaceUnit(expr_ref, defs), cache) {
        Error(err) -> Error("Typecheck Error: " <> string.inspect(err))
        Ok(#(unit, _next_cache)) -> {
          use def <- result.try(list.key_find(unit.defs, expr_ref) |> result.replace_error("No def found"))
          let mod_name = module_name_for(expr_ref)
          let _ = unload_binary(mod_name)
          case compile_definition(new_compiler(), def, expr_ref) {
            Error(e) -> Error("Compile Error: " <> string.inspect(e))
            Ok(beam) -> case load_binary(mod_name, beam) {
              Error(err) -> Error("Load Error: " <> err)
              Ok(_) -> case eval_module(mod_name) {
                Error(err) -> Error("Runtime Error: " <> err)
                Ok(val_str) -> {
                  let assert ast.TermDef(term: _, typ:) = def
                  Ok(val_str <> " : " <> string.inspect(typ))
                }
              }
            }
          }
        }
      }
    }
  }
}

/// Same as eval_string but uses a unique module name per call for concurrent safety.
pub fn eval_string_unique(expr: String) -> Result(String, String) {
  case parser.parse_string(expr) {
    Error(e) -> Error("Parse Error: " <> e.message)
    Ok(elab_types.SList([elab_types.SVar("define"), elab_types.SVar(name), _val])) ->
      Error("Define not supported in eval endpoint: " <> name)
    Ok(term) -> {
      let unique_id = ffi_unique_integer()
      let ref_name = "repl_expr_" <> int.to_string(unique_id)
      let expr_ref = ref_for_name(ref_name)
      let defs = [#(ref_name, SurfaceTermDef(term))]
      let cache = empty_cache()
      case elab.elaborate_unit(SurfaceUnit(expr_ref, defs), cache) {
        Error(err) -> Error("Typecheck Error: " <> string.inspect(err))
        Ok(#(unit, _next_cache)) -> {
          use def <- result.try(list.key_find(unit.defs, expr_ref) |> result.replace_error("No def found"))
          let mod_name = module_name_for(expr_ref)
          case compile_definition(new_compiler(), def, expr_ref) {
            Error(e) -> Error("Compile Error: " <> string.inspect(e))
            Ok(beam) -> case load_binary(mod_name, beam) {
              Error(err) -> Error("Load Error: " <> err)
              Ok(_) -> case eval_module(mod_name) {
                Error(err) -> Error("Runtime Error: " <> err)
                Ok(val_str) -> {
                  let assert ast.TermDef(term: _, typ:) = def
                  Ok(val_str <> " : " <> string.inspect(typ))
                }
              }
            }
          }
        }
      }
    }
  }
}

@external(erlang, "erlang", "unique_integer")
fn ffi_unique_integer() -> Int

pub fn start_repl() -> Nil {
  io.println("=== Gleamunison Interactive REPL ===\nType expressions or 'exit'/'quit' to exit.")
  let init_defs = [
    #("Console", elab_types.SurfaceAbilityDef("Console", [
      elab_types.SurfaceOp("print", [elab_types.TBuiltin(elab_types.TText)], elab_types.TBuiltin(elab_types.TInt))
    ])),
    #("add", SurfaceTermDef(elab_types.SRef(builtin_int_add()))),
    #("+", SurfaceTermDef(elab_types.SRef(builtin_int_add()))),
    #("read_line", SurfaceTermDef(elab_types.SRef(builtin_io_read_line()))),
    #("spawn", SurfaceTermDef(elab_types.SRef(builtin_process_spawn()))),
    #("self", SurfaceTermDef(elab_types.SRef(builtin_process_self()))),
    #("send", SurfaceTermDef(elab_types.SRef(builtin_process_send()))),
    #("recv", SurfaceTermDef(elab_types.SRef(builtin_process_recv()))),
    #("sleep", SurfaceTermDef(elab_types.SRef(builtin_timer_sleep()))),
    #("now", SurfaceTermDef(elab_types.SRef(builtin_timer_now()))),
    // Arithmetic
    #("sub", SurfaceTermDef(elab_types.SRef(builtin_sub()))),
    #("mul", SurfaceTermDef(elab_types.SRef(builtin_mul()))),
    #("div", SurfaceTermDef(elab_types.SRef(builtin_div()))),
    #("mod", SurfaceTermDef(elab_types.SRef(builtin_mod()))),
    // Comparison
    #("eq?", SurfaceTermDef(elab_types.SRef(builtin_eq()))),
    #("lt?", SurfaceTermDef(elab_types.SRef(builtin_lt()))),
    #("gt?", SurfaceTermDef(elab_types.SRef(builtin_gt()))),
    // Boolean
    #("and", SurfaceTermDef(elab_types.SRef(builtin_and()))),
    #("or", SurfaceTermDef(elab_types.SRef(builtin_or()))),
    #("not", SurfaceTermDef(elab_types.SRef(builtin_not()))),
    // Strings (151-160)
    #("string-concat", SurfaceTermDef(elab_types.SRef(builtin_string_concat()))),
    #("string-length", SurfaceTermDef(elab_types.SRef(builtin_string_length()))),
    #("string-contains?", SurfaceTermDef(elab_types.SRef(builtin_string_contains()))),
    #("string-slice", SurfaceTermDef(elab_types.SRef(builtin_string_slice()))),
    #("string-upcase", SurfaceTermDef(elab_types.SRef(builtin_string_upcase()))),
    #("string-downcase", SurfaceTermDef(elab_types.SRef(builtin_string_downcase()))),
    #("string-replace", SurfaceTermDef(elab_types.SRef(builtin_string_replace()))),
    #("string-split", SurfaceTermDef(elab_types.SRef(builtin_string_split()))),
    #("string-trim", SurfaceTermDef(elab_types.SRef(builtin_string_trim()))),
    #("string->int", SurfaceTermDef(elab_types.SRef(builtin_string_to_int()))),
    // Lists (161-170)
    #("list-length", SurfaceTermDef(elab_types.SRef(builtin_list_length()))),
    #("list-reverse", SurfaceTermDef(elab_types.SRef(builtin_list_reverse()))),
    #("list-map", SurfaceTermDef(elab_types.SRef(builtin_list_map()))),
    #("list-filter", SurfaceTermDef(elab_types.SRef(builtin_list_filter()))),
    #("list-fold", SurfaceTermDef(elab_types.SRef(builtin_list_fold()))),
    #("list-append", SurfaceTermDef(elab_types.SRef(builtin_list_append()))),
    #("list-flatten", SurfaceTermDef(elab_types.SRef(builtin_list_flatten()))),
    #("list-member?", SurfaceTermDef(elab_types.SRef(builtin_list_member()))),
    #("range", SurfaceTermDef(elab_types.SRef(builtin_list_range()))),
    #("list-sort", SurfaceTermDef(elab_types.SRef(builtin_list_sort()))),
    // Data structures (171-180)
    #("pair", SurfaceTermDef(elab_types.SRef(builtin_pair()))),
    #("fst", SurfaceTermDef(elab_types.SRef(builtin_fst()))),
    #("snd", SurfaceTermDef(elab_types.SRef(builtin_snd()))),
    #("left", SurfaceTermDef(elab_types.SRef(builtin_left()))),
    #("right", SurfaceTermDef(elab_types.SRef(builtin_right()))),
    #("dict-new", SurfaceTermDef(elab_types.SRef(builtin_dict_new()))),
    #("dict-get", SurfaceTermDef(elab_types.SRef(builtin_dict_get()))),
    #("dict-set", SurfaceTermDef(elab_types.SRef(builtin_dict_set()))),
    #("set-new", SurfaceTermDef(elab_types.SRef(builtin_set_new()))),
    #("set-insert", SurfaceTermDef(elab_types.SRef(builtin_set_insert()))),
  ]
  let #(ld, cb, cache) = bootstrap_defs(init_defs, loader.new_loader(), codebase.empty(), empty_cache())
  repl_loop(compile.new(), ld, cb, cache, init_defs)
}

fn bootstrap_defs(defs, loader, cb, cache) {
  list.fold(defs, #(loader, cb, cache), fn(acc, pair) {
    let #(name, val_def) = pair
    let #(curr_ld, curr_cb, curr_cache) = acc
    case val_def {
      SurfaceTermDef(val) -> {
        case handle_define(name, val, curr_ld, curr_cb, curr_cache, []) {
          Ok(#(next_ld, next_cb, next_cache, _)) -> #(next_ld, next_cb, next_cache)
          Error(_) -> acc
        }
      }
      elab_types.SurfaceAbilityDef(_, _) -> {
        let name_ref = ref_for_name(name)
        case elab.elaborate_unit(SurfaceUnit(ref_for_name("repl_expr"), [#(name, val_def)]), curr_cache) {
          Error(_) -> acc
          Ok(#(unit, next_cache)) -> {
            let assert Ok(def) = list.key_find(unit.defs, name_ref)
            let computed_ref = Ref(hash_of_definition(def))
            case insert(curr_cb, ast.Unit(computed_ref, [#(computed_ref, def)])) {
              Error(_) -> acc
              Ok(next_cb) -> case ensure_loaded(curr_ld, name_ref, def) {
                Error(_) -> acc
                Ok(next_ld) -> #(next_ld, next_cb, next_cache)
              }
            }
          }
        }
      }
      _ -> acc
    }
  })
}

fn count_brackets(str: String, in_string: Bool, depth: Int) -> Int {
  case string.pop_grapheme(str) {
    Ok(#("(", rest)) -> case in_string {
      True -> count_brackets(rest, True, depth)
      False -> count_brackets(rest, False, depth + 1)
    }
    Ok(#(")", rest)) -> case in_string {
      True -> count_brackets(rest, True, depth)
      False -> count_brackets(rest, False, depth - 1)
    }
    Ok(#("\"", rest)) -> count_brackets(rest, !in_string, depth)
    Ok(#("'", rest)) -> {
      // Skip char literals: 'a is not a string
      case in_string {
        True -> count_brackets(rest, True, depth)
        False -> count_brackets(rest, False, depth)
      }
    }
    Ok(#(_, rest)) -> count_brackets(rest, in_string, depth)
    Error(Nil) -> depth
  }
}

fn read_expression() -> Result(String, Nil) {
  case read_line("gleamunison> ") {
    Error(_) -> Error(Nil)
    Ok(first) -> accumulate_expr(string.trim(first))
  }
}

fn accumulate_expr(acc: String) -> Result(String, Nil) {
  case count_brackets(acc, False, 0) {
    0 -> Ok(acc)
    _ -> {
      case read_line("...> ") {
        Error(_) -> Ok(acc)
        Ok(next) -> accumulate_expr(acc <> "\n" <> next)
      }
    }
  }
}

fn repl_loop(compiler, loader, cb, cache, prev_defs) -> Nil {
  case read_expression() {
    Error(_) -> io.println("\nBye!")
    Ok(line) -> {
      let trimmed = string.trim(line)
      case trimmed {
        "exit" | "quit" -> io.println("Bye!")
        "" -> repl_loop(compiler, loader, cb, cache, prev_defs)
        _ -> case handle_line(trimmed, compiler, loader, cb, cache, prev_defs) {
          Ok(#(next_ld, next_cb, next_cache, next_defs)) ->
            repl_loop(compiler, next_ld, next_cb, next_cache, next_defs)
          Error(_) ->
            repl_loop(compiler, loader, cb, cache, prev_defs)
        }
      }
    }
  }
}

fn handle_line(input: String, _compiler, loader, cb, cache, prev_defs) {
  case parser.parse_string(input) {
    Error(err) -> {
      case err.message {
        "Empty input" -> Error(Nil)
        _ -> {
          io.println("Parse Error: " <> err.message <> " at line " <> string.inspect(err.line))
          Error(Nil)
        }
      }
    }
    Ok(elab_types.SList([elab_types.SVar("define"), elab_types.SVar(name), val])) -> {
      case handle_define(name, val, loader, cb, cache, prev_defs) {
        Ok(res) -> {
          io.println(name <> " defined.")
          Ok(res)
        }
        Error(_) -> Error(Nil)
      }
    }
    Ok(term) ->
      handle_eval(term, loader, cb, cache, prev_defs)
  }
}

fn handle_define(name: String, val, loader, cb, cache, prev_defs) {
  let name_ref = ref_for_name(name)
  // Remove any existing definition with the same name to prevent duplicates
  let prev_defs = list.filter(prev_defs, fn(pair) {
    let #(n, _) = pair
    n != name
  })
  let defs = [#(name, SurfaceTermDef(val)), ..prev_defs]
  case elab.elaborate_unit(SurfaceUnit(ref_for_name("repl_expr"), defs), cache) {
    Error(err) -> {
      io.println("Typecheck Error: " <> string.inspect(err))
      Error(Nil)
    }
    Ok(#(unit, next_cache)) -> {
      use def <- result.try(list.key_find(unit.defs, name_ref) |> result.replace_error(Nil))
      // Force-purge and reload so redefinitions take effect
      let mod_name = module_name_for(name_ref)
      let _ = unload_binary(mod_name)
      case compile_definition(new_compiler(), def, name_ref) {
        Error(e) -> {
          io.println("Compile Error: " <> string.inspect(e))
          Error(Nil)
        }
        Ok(beam) -> case load_binary(mod_name, beam) {
          Error(err) -> {
            io.println("Load Error: " <> err)
            Error(Nil)
          }
          Ok(_) -> Ok(#(loader, cb, next_cache, defs))
        }
      }
    }
  }
}

fn handle_eval(term, loader, cb, cache, prev_defs) {
  let expr_ref = ref_for_name("repl_expr")
  let defs = [#("repl_expr", SurfaceTermDef(term)), ..prev_defs]
  case elab.elaborate_unit(SurfaceUnit(expr_ref, defs), cache) {
    Error(err) -> {
      io.println("Typecheck Error: " <> string.inspect(err))
      Error(Nil)
    }
    Ok(#(unit, next_cache)) -> {
      use def <- result.try(list.key_find(unit.defs, expr_ref) |> result.replace_error(Nil))
      let mod_name = module_name_for(expr_ref)
      // Force-purge and reload so each expression gets a fresh module
      let _ = unload_binary(mod_name)
      case compile_definition(new_compiler(), def, expr_ref) {
        Error(e) -> {
          io.println("Compile Error: " <> string.inspect(e))
          Error(Nil)
        }
        Ok(beam) -> case load_binary(mod_name, beam) {
          Error(err) -> {
            io.println("Load Error: " <> err)
            Error(Nil)
          }
          Ok(_) -> case eval_module(mod_name) {
            Error(err) -> {
              io.println("Runtime Error: " <> err)
              Error(Nil)
            }
            Ok(val_str) -> {
              let assert ast.TermDef(term: _, typ:) = def
              io.println(val_str <> " : " <> string.inspect(typ))
              Ok(#(loader, cb, next_cache, prev_defs))
            }
          }
        }
      }
    }
  }
}
