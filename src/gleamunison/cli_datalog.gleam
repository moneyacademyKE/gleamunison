import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleamunison/elab_types.{SurfaceTermDef}
import gleamunison/lexer
import gleamunison/parser
import gleamunison/repl_eval
import gleamunison/types.{type TypeCache, empty_cache}
import gleamunison/verify
import simplifile

/// The native datalog engine (ADR-0062) lives in userspace Lisp under
/// gleamunison_datalog/src. This CLI loads it, then the user's script, and
/// prints the value of every top-level expression. Paths are relative to
/// the current working directory.
const engine_files = [
  "gleamunison_datalog/src/01_core.lisp",
  "gleamunison_datalog/src/02_index.lisp",
  "gleamunison_datalog/src/03_transact.lisp",
  "gleamunison_datalog/src/04_schema.lisp",
  "gleamunison_datalog/src/05_query.lisp",
  "gleamunison_datalog/src/06_aggregate.lisp",
  "gleamunison_datalog/src/07_pull.lisp",
  "gleamunison_datalog/src/08_temporal.lisp",
  "gleamunison_datalog/src/09_rules.lisp",
  "gleamunison_datalog/src/10_graph.lisp",
  "gleamunison_datalog/src/11_vector.lisp",
  "gleamunison_datalog/src/12_bm25.lisp",
  "gleamunison_datalog/src/13_actor.lisp",
]

pub fn run(script_path: String) -> Result(String, String) {
  use engine_src <- result.try(read_engine())
  use script_src <- result.try(
    simplifile.read(script_path)
    |> result.replace_error("cannot read script: " <> script_path),
  )
  eval_source(engine_src <> "\n" <> script_src)
}

fn read_engine() -> Result(String, String) {
  list.try_fold(engine_files, "", fn(acc, path) {
    case simplifile.read(path) {
      Ok(content) -> Ok(acc <> "\n" <> content)
      Error(_) ->
        Error(
          "engine source not found: "
          <> path
          <> " (run from the gleamunison repo root)",
        )
    }
  })
}

fn eval_source(source: String) -> Result(String, String) {
  let tokens = lexer.tokenize(source)
  use sexprs <- result.try(parse_all(tokens, []))
  use terms <- result.try(
    list.try_map(sexprs, fn(s) {
      parser.sexpr_to_term(s)
      |> result.map_error(fn(e) {
        "parse: " <> e.message <> " at line " <> int.to_string(e.line)
      })
    }),
  )
  let #(cache, defs) =
    repl_eval.bootstrap_defs(verify.get_init_defs(), empty_cache())
  run_terms(terms, cache, defs, [])
}

fn parse_all(tokens, acc) {
  case tokens {
    [] -> Ok(list.reverse(acc))
    _ ->
      case parser.parse_sexpr(tokens) {
        Ok(#(sexpr, rest)) -> parse_all(rest, [sexpr, ..acc])
        Error(e) ->
          Error(
            "tokenize: "
            <> e.message
            <> " at line "
            <> int.to_string(e.line)
            <> ", col "
            <> int.to_string(e.col),
          )
      }
  }
}

fn run_terms(terms, cache: TypeCache, defs, out: List(String)) {
  case terms {
    [] -> Ok(string.join(list.reverse(out), "\n"))
    [term, ..rest] -> {
      case term {
        elab_types.SList([
          elab_types.SLoc(elab_types.SVar("define"), _),
          elab_types.SLoc(elab_types.SVar(name), _),
          val,
        ]) -> {
          case repl_eval.handle_define(name, val, cache, defs) {
            Ok(#(nc, ndefs)) ->
              run_terms(rest, nc, ndefs, ["(defined " <> name <> ")", ..out])
            Error(err) -> Error("define " <> name <> ": " <> err)
          }
        }
        elab_types.SList([elab_types.SVar("define"), elab_types.SVar(name), val]) -> {
          case repl_eval.handle_define(name, val, cache, defs) {
            Ok(#(nc, ndefs)) ->
              run_terms(rest, nc, ndefs, ["(defined " <> name <> ")", ..out])
            Error(err) -> Error("define " <> name <> ": " <> err)
          }
        }
        _ -> {
          case repl_eval.do_eval(term, "datalog_expr", cache, defs) {
            Ok(#(val_str, _, nc)) -> run_terms(rest, nc, defs, [val_str, ..out])
            Error(err) -> Error("eval: " <> err)
          }
        }
      }
    }
  }
}
