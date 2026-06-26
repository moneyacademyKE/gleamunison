import gleam/io
import gleam/string
import gleam/list
import gleam/result
import gleamunison/identity.{type DefinitionRef, Ref, builtin_int_add, builtin_io_read_line}
import gleamunison/ast
import gleamunison/parser
import gleamunison/elaborate as elab
import gleamunison/elab_types.{SurfaceUnit, SurfaceTermDef}
import gleamunison/codebase.{insert, hash_of_definition}
import gleamunison/compile.{module_name_for}
import gleamunison/loader.{ensure_loaded}
import gleamunison/types.{empty_cache}

@external(erlang, "gleamunison_ffi", "string_to_binary")
fn string_to_binary(s: String) -> BitArray

@external(erlang, "gleamunison_repl_ffi", "eval_module")
fn eval_module(mod_name: String) -> Result(String, String)

@external(erlang, "gleamunison_repl_ffi", "read_line")
fn read_line(prompt: String) -> Result(String, Nil)

fn ref_for_name(name: String) -> DefinitionRef {
  Ref(identity.hash_bytes(string_to_binary(name)))
}

pub fn start_repl() -> Nil {
  io.println("=== Gleamunison Interactive REPL ===\nType expressions or 'exit'/'quit' to exit.")
  let init_defs = [
    #("Console", elab_types.SurfaceAbilityDef("Console", [
      elab_types.SurfaceOp("print", [elab_types.TBuiltin(elab_types.TText)], elab_types.TBuiltin(elab_types.TInt))
    ])),
    #("add", SurfaceTermDef(elab_types.SRef(builtin_int_add()))),
    #("read_line", SurfaceTermDef(elab_types.SRef(builtin_io_read_line()))),
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

fn repl_loop(compiler, loader, cb, cache, prev_defs) -> Nil {
  case read_line("gleamunison> ") {
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
      io.println("Parse Error: " <> err.message <> " at line " <> string.inspect(err.line))
      Error(Nil)
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
  let defs = [#(name, SurfaceTermDef(val)), ..prev_defs]
  case elab.elaborate_unit(SurfaceUnit(ref_for_name("repl_expr"), defs), cache) {
    Error(err) -> {
      io.println("Typecheck Error: " <> string.inspect(err))
      Error(Nil)
    }
    Ok(#(unit, next_cache)) -> {
      use def <- result.try(list.key_find(unit.defs, name_ref) |> result.replace_error(Nil))
      let computed_ref = Ref(hash_of_definition(def))
      use next_cb <- result.try(insert(cb, ast.Unit(computed_ref, [#(computed_ref, def)])) |> result.replace_error(Nil))
      use next_ld <- result.try(ensure_loaded(loader, name_ref, def) |> result.map_error(fn(p) { io.println("Load Error: " <> string.inspect(p.1)) }))
      Ok(#(next_ld, next_cb, next_cache, defs))
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
      use next_ld <- result.try(ensure_loaded(loader, expr_ref, def) |> result.map_error(fn(p) { io.println("Load Error: " <> string.inspect(p.1)) }))
      case eval_module(module_name_for(expr_ref)) {
        Error(err) -> {
          io.println("Runtime Error: " <> err)
          Error(Nil)
        }
        Ok(val_str) -> {
          let assert ast.TermDef(term: _, typ:) = def
          io.println(val_str <> " : " <> string.inspect(typ))
          Ok(#(next_ld, cb, next_cache, prev_defs))
        }
      }
    }
  }
}
