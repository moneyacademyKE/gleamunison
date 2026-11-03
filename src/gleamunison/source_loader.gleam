//// Parse a definitions-only source payload with the bootstrap environment.
//// Evaluation belongs to the test/evidence phase, not source admission.

import gleam/list
import gleam/result
import gleamunison/elab_types.{type SurfaceDef, type SurfaceTerm}
import gleamunison/lexer
import gleamunison/repl_eval
import gleamunison/types.{type TypeCache, empty_cache}
import gleamunison/verify

pub type LoadedSource {
  LoadedSource(
    cache: TypeCache,
    definitions: List(#(String, SurfaceDef)),
    names: List(String),
  )
}

pub fn load(source: String) -> Result(LoadedSource, String) {
  let tokens = lexer.tokenize(source)
  use exprs <- result.try(
    verify.parse_all_sexprs(tokens, [])
    |> result.map_error(fn(e) { "Parse Error: " <> lexer.describe_error(e) }),
  )
  use terms <- result.try(
    verify.terms_from_sexprs(exprs, [])
    |> result.map_error(fn(e) {
      "S-Expression Error: " <> lexer.describe_error(e)
    }),
  )
  use terms <- result.try(verify.require_forms(terms))
  let init_defs = verify.get_init_defs()
  let #(cache, bootstrap) = repl_eval.bootstrap_defs(init_defs, empty_cache())
  use #(cache, definitions) <- result.try(fold_defines(terms, cache, bootstrap))
  Ok(LoadedSource(cache:, definitions:, names: defined_names(terms, [])))
}

fn defined_names(terms: List(SurfaceTerm), acc: List(String)) -> List(String) {
  case terms {
    [] -> list.reverse(acc)
    [term, ..rest] ->
      case term {
        elab_types.SList([elab_types.SVar("define"), elab_types.SVar(name), _]) ->
          defined_names(rest, [name, ..acc])
        _ -> defined_names(rest, acc)
      }
  }
}

fn fold_defines(
  terms: List(SurfaceTerm),
  cache: TypeCache,
  defs: List(#(String, SurfaceDef)),
) -> Result(#(TypeCache, List(#(String, SurfaceDef))), String) {
  case terms {
    [] -> Ok(#(cache, defs))
    [term, ..rest] ->
      case term {
        elab_types.SList([elab_types.SVar("define"), elab_types.SVar(name), val]) ->
          case repl_eval.handle_define(name, val, cache, defs) {
            Ok(#(next_cache, next_defs)) ->
              fold_defines(rest, next_cache, next_defs)
            Error(err) -> Error("Define Error for '" <> name <> "': " <> err)
          }
        _ ->
          Error(
            "file must contain only definitions; add a `(define main ...)`"
            <> " that calls what you want to run",
          )
      }
  }
}
