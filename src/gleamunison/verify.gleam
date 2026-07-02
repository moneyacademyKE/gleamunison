import gleam/list
import gleam/string
import gleamunison/elab_types.{type SurfaceDef, type SurfaceTerm, SurfaceTermDef}
import gleamunison/bootstraps
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
  let init_defs = list.map(bootstraps.get_init_defs_data(), convert_bootstrap_def)
  let assert Ok(compare_term) =
    parser.parse_string("(lam a (lam b (if (eq? a b) 0 (if (lt? a b) -1 1))))")
  list.append(init_defs, [#("compare", SurfaceTermDef(compare_term))])
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
