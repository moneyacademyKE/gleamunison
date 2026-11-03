import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleamunison/elab_types
import gleamunison/lexer
import gleamunison/parser
import gleamunison/repl_eval
import gleamunison/types.{type TypeCache, empty_cache}
import gleamunison/verify
import simplifile

/// The native datalog engine (ADR-0062) lives in userspace Lisp, shipped as
/// priv/datalog (source of truth: gleamunison_datalog/src). This CLI loads
/// it, then the user's script, and prints the value of every top-level
/// expression. Engine resolution is handled by read_engine/0.
const engine_files = [
  "01_core.lisp",
  "02_index.lisp",
  "03_transact.lisp",
  "04_schema.lisp",
  "05_query.lisp",
  "06_aggregate.lisp",
  "07_pull.lisp",
  "08_temporal.lisp",
  "09_rules.lisp",
  "10_graph.lisp",
  "11_vector.lisp",
  "12_bm25.lisp",
  "13_actor.lisp",
]

pub fn run(script_path: String) -> Result(String, String) {
  use engine_src <- result.try(read_engine())
  use script_src <- result.try(
    simplifile.read(script_path)
    |> result.replace_error("cannot read script: " <> script_path),
  )
  // The engine is infrastructure, not the user's program. Concatenating both
  // sources and printing every top-level value meant 124 `(defined ...)` lines
  // of engine setup reached stdout before the script's own answer, so the
  // command could not be piped anywhere. Load the engine silently, then print
  // only what the script evaluates.
  let #(cache, defs) =
    repl_eval.bootstrap_defs(verify.get_init_defs(), empty_cache())
  use #(_, cache, defs) <- result.try(load_engine(engine_src, cache, defs))
  eval_script(script_src, cache, defs)
}

fn load_engine(
  source: String,
  cache: TypeCache,
  defs: List(#(String, elab_types.SurfaceDef)),
) -> Result(
  #(String, TypeCache, List(#(String, elab_types.SurfaceDef))),
  String,
) {
  use terms <- result.try(parse_source(source))
  run_terms(terms, cache, defs, [], False)
}

fn eval_script(
  source: String,
  cache: TypeCache,
  defs: List(#(String, elab_types.SurfaceDef)),
) -> Result(String, String) {
  use terms <- result.try(parse_source(source))
  use #(out, _, _) <- result.try(run_terms(terms, cache, defs, [], True))
  Ok(out)
}

fn parse_source(
  source: String,
) -> Result(List(elab_types.SurfaceTerm), String) {
  let tokens = lexer.tokenize(source)
  use sexprs <- result.try(parse_all(tokens, []))
  list.try_map(sexprs, fn(s) {
    parser.sexpr_to_term(s)
    |> result.map_error(fn(e) {
      "parse: " <> e.message <> " at line " <> int.to_string(e.line)
    })
  })
}

@external(erlang, "gleamunison_engine_locator", "read_embedded")
fn read_embedded(name: String) -> Result(String, Nil)

@external(erlang, "gleamunison_engine_locator", "priv_datalog_dir")
fn priv_datalog_dir() -> Result(String, Nil)

/// Load the engine from the first carrier that has it: the escript archive
/// (any working directory), the application priv dir (Hex consumers), then
/// the repository (priv/datalog, then the source of truth).
pub fn read_engine() -> Result(String, String) {
  case read_embedded_engine() {
    Ok(source) -> Ok(source)
    Error(_) -> read_disk_engine(candidate_dirs())
  }
}

fn read_embedded_engine() -> Result(String, Nil) {
  list.try_fold(engine_files, "", fn(acc, name) {
    case read_embedded("priv/datalog/" <> name) {
      Ok(content) -> Ok(acc <> "\n" <> content)
      Error(_) -> Error(Nil)
    }
  })
}

fn candidate_dirs() -> List(String) {
  let app_dir = case priv_datalog_dir() {
    Ok(dir) -> [dir]
    Error(_) -> []
  }
  list.append(app_dir, ["priv/datalog", "gleamunison_datalog/src"])
}

fn read_disk_engine(dirs: List(String)) -> Result(String, String) {
  case dirs {
    [] ->
      Error(
        "datalog engine not found: tried the escript archive, the application priv dir, priv/datalog and gleamunison_datalog/src",
      )
    [dir, ..rest] ->
      case read_engine_dir(dir) {
        Ok(source) -> Ok(source)
        Error(_) -> read_disk_engine(rest)
      }
  }
}

fn read_engine_dir(dir: String) -> Result(String, Nil) {
  list.try_fold(engine_files, "", fn(acc, name) {
    case simplifile.read(dir <> "/" <> name) {
      Ok(content) -> Ok(acc <> "\n" <> content)
      Error(_) -> Error(Nil)
    }
  })
}

/// Evaluate one self-contained source, printing every top-level value. Kept
/// for callers that want the whole program's output, including defines.
pub fn eval_source(source: String) -> Result(String, String) {
  use terms <- result.try(parse_source(source))
  let #(cache, defs) =
    repl_eval.bootstrap_defs(verify.get_init_defs(), empty_cache())
  use #(out, _, _) <- result.try(run_terms(terms, cache, defs, [], True))
  Ok(out)
}

fn parse_all(tokens, acc) {
  case tokens {
    [] -> Ok(list.reverse(acc))
    _ ->
      case parser.parse_sexpr(tokens) {
        Ok(#(sexpr, rest)) -> parse_all(rest, [sexpr, ..acc])
        Error(e) -> Error("tokenize: " <> lexer.describe_error(e))
      }
  }
}

fn run_terms(
  terms: List(elab_types.SurfaceTerm),
  cache: TypeCache,
  defs: List(#(String, elab_types.SurfaceDef)),
  out: List(String),
  echo_defines: Bool,
) -> Result(
  #(String, TypeCache, List(#(String, elab_types.SurfaceDef))),
  String,
) {
  case terms {
    [] -> Ok(#(string.join(list.reverse(out), "\n"), cache, defs))
    [term, ..rest] -> {
      case term {
        elab_types.SList([
          elab_types.SLoc(elab_types.SVar("define"), _),
          elab_types.SLoc(elab_types.SVar(name), _),
          val,
        ]) -> {
          case repl_eval.handle_define(name, val, cache, defs) {
            Ok(#(nc, ndefs)) ->
              run_terms(
                rest,
                nc,
                ndefs,
                case echo_defines {
                  True -> ["(defined " <> name <> ")", ..out]
                  False -> out
                },
                echo_defines,
              )
            Error(err) -> Error("define " <> name <> ": " <> err)
          }
        }
        elab_types.SList([elab_types.SVar("define"), elab_types.SVar(name), val]) -> {
          case repl_eval.handle_define(name, val, cache, defs) {
            Ok(#(nc, ndefs)) ->
              run_terms(
                rest,
                nc,
                ndefs,
                case echo_defines {
                  True -> ["(defined " <> name <> ")", ..out]
                  False -> out
                },
                echo_defines,
              )
            Error(err) -> Error("define " <> name <> ": " <> err)
          }
        }
        _ -> {
          case repl_eval.do_eval(term, "datalog_expr", cache, defs) {
            Ok(#(val_str, _, nc)) ->
              run_terms(rest, nc, defs, [val_str, ..out], echo_defines)
            Error(err) -> Error("eval: " <> err)
          }
        }
      }
    }
  }
}
