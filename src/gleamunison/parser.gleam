import gleam/list
import gleam/result
import gleam/string
import gleamunison/elab_types.{
  type SurfaceTerm, SCase, SFloat, SInt, SLambda, SLet, SList, SMatch,
  SPConstructor, SPInt, SPText, SPVar, SVar,
}
import gleamunison/lexer.{
  type ParseError, type Token, type TokenInfo, FloatVal, IntVal, LParen,
  ParseError, Quote, RParen, Symbol,
}

@external(erlang, "gleamunison_ffi", "string_to_binary")
fn string_to_binary(s: String) -> BitArray

pub type SExpr {
  SAtom(Token, line: Int, col: Int)
  SListExpr(List(SExpr), line: Int, col: Int)
}

pub fn parse_sexpr(
  tokens: List(TokenInfo),
) -> Result(#(SExpr, List(TokenInfo)), ParseError) {
  case tokens {
    [] -> Error(ParseError("Unexpected EOF", 1, 1))
    [lexer.TokenInfo(LParen, l, c), ..rest] -> {
      use #(exprs, rest2) <- result.try(parse_list(rest, []))
      Ok(#(SListExpr(exprs, l, c), rest2))
    }
    [lexer.TokenInfo(RParen, l, c), ..] ->
      Error(ParseError("Unexpected )", l, c))
    [lexer.TokenInfo(Quote, l, c), ..rest] -> {
      case parse_sexpr(rest) {
        Ok(#(expr, rest2)) ->
          Ok(#(SListExpr([SAtom(Symbol("quote"), l, c), expr], l, c), rest2))
        Error(e) -> Error(e)
      }
    }
    [lexer.TokenInfo(other, l, c), ..rest] -> Ok(#(SAtom(other, l, c), rest))
  }
}

fn parse_list(tokens, acc) {
  case tokens {
    [] -> Error(ParseError("Unclosed (", 1, 1))
    [lexer.TokenInfo(RParen, _, _), ..rest] -> Ok(#(list.reverse(acc), rest))
    _ -> {
      use #(expr, rest) <- result.try(parse_sexpr(tokens))
      parse_list(rest, [expr, ..acc])
    }
  }
}

pub fn sexpr_to_term(sexpr: SExpr) -> Result(SurfaceTerm, ParseError) {
  case sexpr {
    SAtom(IntVal(n), _, _) -> Ok(SInt(n))
    SAtom(FloatVal(f), _, _) -> Ok(SFloat(f))
    SAtom(Symbol(name), _, _) -> {
      case string.starts_with(name, "\"") && string.ends_with(name, "\"") {
        True -> {
          let inner = string.slice(name, 1, string.length(name) - 2)
          Ok(elab_types.SText(string_to_binary(inner)))
        }
        False -> Ok(SVar(name))
      }
    }
    SAtom(_, l, c) -> Error(ParseError("Invalid atom", l, c))
    SListExpr(exprs, _l, _c) -> {
      case exprs {
        [SAtom(Symbol("let"), _, _), SAtom(Symbol(name), _, _), val, body] -> {
          use val_t <- result.try(sexpr_to_term(val))
          use body_t <- result.try(sexpr_to_term(body))
          Ok(SLet(name, val_t, body_t))
        }
        [SAtom(Symbol("lam"), _, _), SAtom(Symbol(name), _, _), body] -> {
          use body_t <- result.try(sexpr_to_term(body))
          Ok(SLambda(name, body_t))
        }
        [SAtom(Symbol("define"), _, _), SAtom(Symbol(name), _, _), val] -> {
          use val_t <- result.try(sexpr_to_term(val))
          Ok(SList([SVar("define"), SVar(name), val_t]))
        }
        [SAtom(Symbol("if"), _, _), cond, then_expr, else_expr] -> {
          use cond_t <- result.try(sexpr_to_term(cond))
          use then_t <- result.try(sexpr_to_term(then_expr))
          use else_t <- result.try(sexpr_to_term(else_expr))
          Ok(
            elab_types.SMatch(cond_t, [
              elab_types.SCase(elab_types.SPInt(1), then_t),
              elab_types.SCase(elab_types.SPVar("_"), else_t),
            ]),
          )
        }
        [
          SAtom(Symbol("do"), _, _),
          SAtom(Symbol(ab), _, _),
          SAtom(Symbol(op), _, _),
          ..args
        ] -> {
          use parsed_args <- result.try(list.try_map(args, sexpr_to_term))
          Ok(elab_types.SDo(ab, op, parsed_args))
        }
        [SAtom(Symbol("handle"), _, _), comp, handler, SAtom(Symbol(ab), _, _)] -> {
          use comp_t <- result.try(sexpr_to_term(comp))
          use handler_t <- result.try(sexpr_to_term(handler))
          Ok(elab_types.SHandle(comp_t, handler_t, ab))
        }
        [SAtom(Symbol("type"), _, _), SAtom(Symbol(type_name), _, _), ..ctors] -> {
          use ctor_terms <- result.try(list.try_map(ctors, sexpr_to_term))
          Ok(SList([SVar("type"), SVar(type_name), ..ctor_terms]))
        }
        [SAtom(Symbol("list"), _, _), ..rest] -> {
          case list.try_map(rest, sexpr_to_term) {
            Ok(terms) -> Ok(SList(terms))
            Error(e) -> Error(e)
          }
        }
        [SAtom(Symbol("match"), _, _), scrutinee, ..cases] -> {
          use scrutinee_t <- result.try(sexpr_to_term(scrutinee))
          use parsed_cases <- result.try(
            list.try_map(cases, fn(case_expr) {
              case case_expr {
                SListExpr([pat_expr, body_expr], _, _) -> {
                  use pat <- result.try(sexpr_to_pattern(pat_expr))
                  use body <- result.try(sexpr_to_term(body_expr))
                  Ok(SCase(pattern: pat, body: body))
                }
                _ -> Error(ParseError("Invalid match case", 0, 0))
              }
            }),
          )
          Ok(SMatch(scrutinee_t, parsed_cases))
        }
        [first, ..rest] -> {
          use f_term <- result.try(sexpr_to_term(first))
          list.try_fold(rest, f_term, fn(acc, arg) {
            use arg_term <- result.try(sexpr_to_term(arg))
            Ok(elab_types.SApply(acc, arg_term))
          })
        }
        [] -> Ok(SList([]))
      }
    }
  }
}

fn sexpr_to_pattern(sexpr: SExpr) -> Result(elab_types.SPattern, ParseError) {
  case sexpr {
    SAtom(IntVal(n), _, _) -> Ok(SPInt(n))
    SAtom(Symbol(name), _, _) -> {
      case string.starts_with(name, "\"") && string.ends_with(name, "\"") {
        True -> {
          let inner = string.slice(name, 1, string.length(name) - 2)
          Ok(SPText(string_to_binary(inner)))
        }
        False -> Ok(SPVar(name))
      }
    }
    SListExpr([SAtom(Symbol(ctor_name), _, _), ..args], _, _) -> {
      use parsed_args <- result.try(list.try_map(args, sexpr_to_pattern))
      Ok(SPConstructor(ctor_name, parsed_args))
    }
    _ -> Error(ParseError("Invalid pattern", 0, 0))
  }
}

pub fn parse_string(input: String) -> Result(SurfaceTerm, ParseError) {
  let tokens = lexer.tokenize(input)
  case tokens {
    [] -> Error(ParseError("Empty input", 0, 0))
    _ ->
      case parse_sexpr(tokens) {
        Ok(#(sexpr, [])) -> sexpr_to_term(sexpr)
        Ok(#(_, [lexer.TokenInfo(_, l, c), ..])) ->
          Error(ParseError("Extra tokens after expression", l, c))
        Error(e) -> Error(e)
      }
  }
}
