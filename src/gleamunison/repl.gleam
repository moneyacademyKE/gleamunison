import gleam/int
import gleam/io
import gleam/list
import gleam/string
import gleamunison/elab_types.{SurfaceTermDef}
import gleamunison/bootstraps
import gleamunison/lexer
import gleamunison/parser
import gleamunison/repl_eval
import gleamunison/repl_io
import gleamunison/type_pretty
import gleamunison/types.{type TypeCache, empty_cache}

@external(erlang, "erlang", "unique_integer")
fn ffi_unique_integer() -> Int

pub fn eval_string(expr: String) -> Result(String, String) {
  case parser.parse_string(expr) {
    Error(e) -> Error(format_parse_error(e))
    Ok(elab_types.SList([elab_types.SVar("define"), elab_types.SVar(name), _])) ->
      Error("Define not supported in eval endpoint: " <> name)
    Ok(term) -> {
      case repl_eval.do_eval(term, "repl_expr", empty_cache(), []) {
        Ok(#(val_str, typ, _)) ->
          Ok(val_str <> " : " <> type_pretty.pretty_print(typ))
        Error(err) -> Error(err)
      }
    }
  }
}

fn format_parse_error(e: lexer.ParseError) -> String {
  let lexer.ParseError(msg, line, col) = e
  case msg {
    "Unexpected EOF" ->
      "[P001] unexpected end of input at line "
      <> int.to_string(line)
      <> ", col "
      <> int.to_string(col)
      <> ". Did you forget a closing parenthesis?"
    "Empty input" ->
      "[P002] empty expression. Type an S-expression or 'help' for available commands."
    _ ->
      case string.contains(msg, "Unclosed") {
        True ->
          "[P003] unclosed parentheses at line "
          <> int.to_string(line)
          <> ", col "
          <> int.to_string(col)
          <> ". Every ( needs a matching )."
        False ->
          "[P004] parse error at line "
          <> int.to_string(line)
          <> ", col "
          <> int.to_string(col)
          <> ": "
          <> msg
      }
  }
}

pub fn eval_string_unique(expr: String) -> Result(String, String) {
  case parser.parse_string(expr) {
    Error(e) -> Error(format_parse_error(e))
    Ok(elab_types.SList([elab_types.SVar("define"), elab_types.SVar(name), _])) ->
      Error("Define not supported in eval endpoint: " <> name)
    Ok(term) -> {
      let unique_id = ffi_unique_integer()
      let ref_name = "repl_expr_" <> int.to_string(unique_id)
      case repl_eval.do_eval(term, ref_name, empty_cache(), []) {
        Ok(#(val_str, typ, _)) ->
          Ok(val_str <> " : " <> type_pretty.pretty_print(typ))
        Error(err) -> Error(err)
      }
    }
  }
}

pub fn start_repl() -> Nil {
  io.println(
    "=== Gleamunison Interactive REPL ===\nType expressions or 'exit'/'quit' to exit. Type 'help' for builtins.",
  )
  let init_defs = list.map(bootstraps.get_init_defs_data(), convert_bootstrap_def)
  let assert Ok(compare_term) =
    parser.parse_string("(lam a (lam b (if (eq? a b) 0 (if (lt? a b) -1 1))))")
  let init_defs =
    list.append(init_defs, [#("compare", SurfaceTermDef(compare_term))])
  let #(cache, bootstrap_list) =
    repl_eval.bootstrap_defs(init_defs, empty_cache())
  repl_loop(cache, bootstrap_list)
}

fn convert_bootstrap_def(
  b: bootstraps.BootstrapDef,
) -> #(String, elab_types.SurfaceDef) {
  case b {
    bootstraps.BAbility(name, ops) -> {
      #(
        name,
        elab_types.SurfaceAbilityDef(
          name,
          list.map(ops, fn(op) {
            elab_types.SurfaceOp(
              op.name,
              list.map(op.inputs, convert_bootstrap_type),
              convert_bootstrap_type(op.output),
            )
          }),
        ),
      )
    }
    bootstraps.BTerm(name, ref) -> {
      #(name, elab_types.SurfaceTermDef(elab_types.SRef(ref)))
    }
  }
}

fn convert_bootstrap_type(t: bootstraps.BootstrapType) -> elab_types.Typ {
  case t {
    bootstraps.BTInt -> elab_types.TBuiltin(elab_types.TInt)
    bootstraps.BTFloat -> elab_types.TBuiltin(elab_types.TFloat)
    bootstraps.BTText -> elab_types.TBuiltin(elab_types.TText)
    bootstraps.BTList -> elab_types.TBuiltin(elab_types.TList)
    bootstraps.BTVar(name) -> elab_types.TVar(name)
  }
}

fn help_text() -> String {
  "Builtins: add + sub mul div mod eq? lt? gt? and or not compare\n"
  <> "Strings:  string-concat string-length string-contains? string-slice\n"
  <> "          string-upcase string-downcase string-replace string-split\n"
  <> "          string-trim string->int\n"
  <> "Lists:    list-length list-reverse list-map list-filter list-fold\n"
  <> "          list-append list-flatten list-member? range list-sort\n"
  <> "Pairs:    pair fst snd left right\n"
  <> "Dicts:    dict-new dict-get dict-set set-new set-insert\n"
  <> "IO:       read_line spawn self send recv sleep now\n"
  <> "FFI:      json-parse http-get file-read\n"
  <> "Abilities: Console(print) State(get set) Math(add sub mul) Show(show)\n"
  <> "Forms:    (define name val) (lam x body) (do Ability op args...)\n"
  <> "          (handle comp handler Ability) (match val cases...)"
}

fn repl_loop(
  cache: TypeCache,
  prev_defs: List(#(String, elab_types.SurfaceDef)),
) -> Nil {
  case repl_io.read_expression() {
    Error(_) -> io.println("\nBye!")
    Ok(line) -> {
      let trimmed = string.trim(line)
      case trimmed {
        "exit" | "quit" -> io.println("Bye!")
        "help" -> {
          io.println(help_text())
          repl_loop(cache, prev_defs)
        }
        "" -> repl_loop(cache, prev_defs)
        _ ->
          case handle_line(trimmed, cache, prev_defs) {
            Ok(#(next_cache, next_defs)) -> repl_loop(next_cache, next_defs)
            Error(_) -> repl_loop(cache, prev_defs)
          }
      }
    }
  }
}

fn handle_line(
  input: String,
  cache: TypeCache,
  prev_defs: List(#(String, elab_types.SurfaceDef)),
) -> Result(#(TypeCache, List(#(String, elab_types.SurfaceDef))), Nil) {
  case parser.parse_string(input) {
    Error(err) -> {
      case err.message {
        "Empty input" -> Error(Nil)
        _ -> {
          io.println(format_parse_error(err))
          Error(Nil)
        }
      }
    }
    Ok(elab_types.SList([elab_types.SVar("define"), elab_types.SVar(name), val])) -> {
      case repl_eval.handle_define(name, val, cache, prev_defs) {
        Ok(#(next_cache, next_defs)) -> {
          io.println(name <> " defined.")
          Ok(#(next_cache, next_defs))
        }
        Error(err) -> {
          io.println(err)
          Error(Nil)
        }
      }
    }
    Ok(term) -> {
      case repl_eval.do_eval(term, "repl_expr", cache, prev_defs) {
        Ok(#(val_str, typ, next_cache)) -> {
          io.println(val_str <> " : " <> type_pretty.pretty_print(typ))
          Ok(#(next_cache, prev_defs))
        }

        Error(err) -> {
          io.println(err)
          Error(Nil)
        }
      }
    }
  }
}
