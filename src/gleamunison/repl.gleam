import gleam/int
import gleam/io
import gleam/list
import gleam/string
import gleamunison/elab_types.{SurfaceTermDef}
import gleamunison/identity.{
  builtin_and, builtin_dict_get, builtin_dict_new, builtin_dict_set, builtin_div,
  builtin_eq, builtin_file_read, builtin_fst, builtin_gt, builtin_http_get,
  builtin_int_add, builtin_io_read_line, builtin_json_parse, builtin_left,
  builtin_list_append, builtin_list_filter, builtin_list_flatten,
  builtin_list_fold, builtin_list_length, builtin_list_map, builtin_list_member,
  builtin_list_range, builtin_list_reverse, builtin_list_sort, builtin_lt,
  builtin_mod, builtin_mul, builtin_not, builtin_or, builtin_pair,
  builtin_process_recv, builtin_process_self, builtin_process_send,
  builtin_process_spawn, builtin_right, builtin_set_insert, builtin_set_new,
  builtin_snd, builtin_string_concat, builtin_string_contains,
  builtin_string_downcase, builtin_string_length, builtin_string_replace,
  builtin_string_slice, builtin_string_split, builtin_string_to_int,
  builtin_string_trim, builtin_string_upcase, builtin_sub, builtin_timer_now,
  builtin_timer_sleep,
}
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
  let init_defs = [
    #(
      "Console",
      elab_types.SurfaceAbilityDef("Console", [
        elab_types.SurfaceOp(
          "print",
          [elab_types.TBuiltin(elab_types.TText)],
          elab_types.TBuiltin(elab_types.TInt),
        ),
      ]),
    ),
    #(
      "State",
      elab_types.SurfaceAbilityDef("State", [
        elab_types.SurfaceOp(
          "get",
          [elab_types.TBuiltin(elab_types.TText)],
          elab_types.TBuiltin(elab_types.TText),
        ),
        elab_types.SurfaceOp(
          "set",
          [
            elab_types.TBuiltin(elab_types.TText),
            elab_types.TBuiltin(elab_types.TText),
          ],
          elab_types.TBuiltin(elab_types.TText),
        ),
      ]),
    ),
    #(
      "Math",
      elab_types.SurfaceAbilityDef("Math", [
        elab_types.SurfaceOp(
          "add",
          [
            elab_types.TBuiltin(elab_types.TInt),
            elab_types.TBuiltin(elab_types.TInt),
          ],
          elab_types.TBuiltin(elab_types.TInt),
        ),
        elab_types.SurfaceOp(
          "sub",
          [
            elab_types.TBuiltin(elab_types.TInt),
            elab_types.TBuiltin(elab_types.TInt),
          ],
          elab_types.TBuiltin(elab_types.TInt),
        ),
        elab_types.SurfaceOp(
          "mul",
          [
            elab_types.TBuiltin(elab_types.TInt),
            elab_types.TBuiltin(elab_types.TInt),
          ],
          elab_types.TBuiltin(elab_types.TInt),
        ),
      ]),
    ),
    #(
      "Show",
      elab_types.SurfaceAbilityDef("Show", [
        elab_types.SurfaceOp(
          "show",
          [elab_types.TVar("a")],
          elab_types.TBuiltin(elab_types.TText),
        ),
      ]),
    ),
    #(
      "Remote",
      elab_types.SurfaceAbilityDef("Remote", [
        elab_types.SurfaceOp(
          "forkAt",
          [elab_types.TVar("location"), elab_types.TVar("a")],
          elab_types.TVar("task"),
        ),
        elab_types.SurfaceOp(
          "await",
          [elab_types.TVar("task")],
          elab_types.TVar("a"),
        ),
        elab_types.SurfaceOp("here", [], elab_types.TVar("location")),
      ]),
    ),
    #("add", SurfaceTermDef(elab_types.SRef(builtin_int_add()))),
    #("+", SurfaceTermDef(elab_types.SRef(builtin_int_add()))),
    #("read_line", SurfaceTermDef(elab_types.SRef(builtin_io_read_line()))),
    #("spawn", SurfaceTermDef(elab_types.SRef(builtin_process_spawn()))),
    #("self", SurfaceTermDef(elab_types.SRef(builtin_process_self()))),
    #("send", SurfaceTermDef(elab_types.SRef(builtin_process_send()))),
    #("recv", SurfaceTermDef(elab_types.SRef(builtin_process_recv()))),
    #("sleep", SurfaceTermDef(elab_types.SRef(builtin_timer_sleep()))),
    #("now", SurfaceTermDef(elab_types.SRef(builtin_timer_now()))),
    #("sub", SurfaceTermDef(elab_types.SRef(builtin_sub()))),
    #("mul", SurfaceTermDef(elab_types.SRef(builtin_mul()))),
    #("div", SurfaceTermDef(elab_types.SRef(builtin_div()))),
    #("mod", SurfaceTermDef(elab_types.SRef(builtin_mod()))),
    #("eq?", SurfaceTermDef(elab_types.SRef(builtin_eq()))),
    #("lt?", SurfaceTermDef(elab_types.SRef(builtin_lt()))),
    #("gt?", SurfaceTermDef(elab_types.SRef(builtin_gt()))),
    #("and", SurfaceTermDef(elab_types.SRef(builtin_and()))),
    #("or", SurfaceTermDef(elab_types.SRef(builtin_or()))),
    #("not", SurfaceTermDef(elab_types.SRef(builtin_not()))),
    #("string-concat", SurfaceTermDef(elab_types.SRef(builtin_string_concat()))),
    #("string-length", SurfaceTermDef(elab_types.SRef(builtin_string_length()))),
    #(
      "string-contains?",
      SurfaceTermDef(elab_types.SRef(builtin_string_contains())),
    ),
    #("string-slice", SurfaceTermDef(elab_types.SRef(builtin_string_slice()))),
    #("string-upcase", SurfaceTermDef(elab_types.SRef(builtin_string_upcase()))),
    #(
      "string-downcase",
      SurfaceTermDef(elab_types.SRef(builtin_string_downcase())),
    ),
    #(
      "string-replace",
      SurfaceTermDef(elab_types.SRef(builtin_string_replace())),
    ),
    #("string-split", SurfaceTermDef(elab_types.SRef(builtin_string_split()))),
    #("string-trim", SurfaceTermDef(elab_types.SRef(builtin_string_trim()))),
    #("string->int", SurfaceTermDef(elab_types.SRef(builtin_string_to_int()))),
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
    #("json-parse", SurfaceTermDef(elab_types.SRef(builtin_json_parse()))),
    #("http-get", SurfaceTermDef(elab_types.SRef(builtin_http_get()))),
    #("file-read", SurfaceTermDef(elab_types.SRef(builtin_file_read()))),
  ]
  let assert Ok(compare_term) =
    parser.parse_string("(lam a (lam b (if (eq? a b) 0 (if (lt? a b) -1 1))))")
  let init_defs =
    list.append(init_defs, [#("compare", SurfaceTermDef(compare_term))])
  let #(cache, bootstrap_list) =
    repl_eval.bootstrap_defs(init_defs, empty_cache())
  repl_loop(cache, bootstrap_list)
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
