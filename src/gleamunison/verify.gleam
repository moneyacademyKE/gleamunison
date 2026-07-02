import gleam/list
import gleam/string
import gleamunison/elab_types.{type SurfaceDef, type SurfaceTerm, SurfaceTermDef}
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
import gleamunison/parser.{type SExpr, parse_sexpr, sexpr_to_term}
import gleamunison/repl_eval
import gleamunison/types.{type TypeCache, empty_cache}
import simplifile

fn parse_all_sexprs(
  tokens: List(lexer.TokenInfo),
  acc: List(SExpr),
) -> Result(List(SExpr), lexer.ParseError) {
  case tokens {
    [] -> Ok(list.reverse(acc))
    _ -> {
      case parse_sexpr(tokens) {
        Ok(#(expr, rest)) -> parse_all_sexprs(rest, [expr, ..acc])
        Error(e) -> Error(e)
      }
    }
  }
}

fn terms_from_sexprs(
  exprs: List(SExpr),
  acc: List(SurfaceTerm),
) -> Result(List(SurfaceTerm), lexer.ParseError) {
  case exprs {
    [] -> Ok(list.reverse(acc))
    [expr, ..rest] -> {
      case sexpr_to_term(expr) {
        Ok(t) -> terms_from_sexprs(rest, [t, ..acc])
        Error(e) -> Error(e)
      }
    }
  }
}

fn verify_terms(
  terms: List(SurfaceTerm),
  cache: TypeCache,
  prev_defs: List(#(String, SurfaceDef)),
) -> Result(#(TypeCache, List(#(String, SurfaceDef))), String) {
  case terms {
    [] -> Ok(#(cache, prev_defs))
    [term, ..rest] -> {
      case term {
        elab_types.SList([
          elab_types.SVar("define"),
          elab_types.SVar(name),
          val,
        ]) -> {
          case repl_eval.handle_define(name, val, cache, prev_defs) {
            Ok(#(next_cache, next_defs)) ->
              verify_terms(rest, next_cache, next_defs)
            Error(err) -> Error("Define Error for '" <> name <> "': " <> err)
          }
        }
        _ -> {
          case repl_eval.do_eval(term, "verify_expr", cache, prev_defs) {
            Ok(#(_, _, next_cache)) -> verify_terms(rest, next_cache, prev_defs)
            Error(err) -> Error("Evaluation Error: " <> err)
          }
        }
      }
    }
  }
}

fn get_init_defs() -> List(#(String, SurfaceDef)) {
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
  list.append(init_defs, [#("compare", SurfaceTermDef(compare_term))])
}

pub fn verify_file(path: String) -> Result(String, String) {
  case simplifile.read(path) {
    Error(e) -> Error("Failed to read file: " <> string.inspect(e))
    Ok(content) -> {
      let tokens = lexer.tokenize(content)
      case parse_all_sexprs(tokens, []) {
        Error(e) ->
          Error(
            "Parse Error: "
            <> e.message
            <> " at line "
            <> string.inspect(e.line)
            <> ", col "
            <> string.inspect(e.col),
          )
        Ok(exprs) -> {
          case terms_from_sexprs(exprs, []) {
            Error(e) ->
              Error(
                "S-Expression Error: "
                <> e.message
                <> " at line "
                <> string.inspect(e.line)
                <> ", col "
                <> string.inspect(e.col),
              )
            Ok(terms) -> {
              let init_defs = get_init_defs()
              let #(cache, bootstrap_list) =
                repl_eval.bootstrap_defs(init_defs, empty_cache())
              case verify_terms(terms, cache, bootstrap_list) {
                Ok(_) -> Ok("Verification successful: " <> path)
                Error(err) -> Error(err)
              }
            }
          }
        }
      }
    }
  }
}
