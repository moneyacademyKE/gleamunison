import gleam/list
import gleam/string
import gleam/int
import gleam/result
import gleamunison/elab_types.{type SurfaceTerm, SInt, SVar, SLet, SLambda, SList}

@external(erlang, "gleamunison_ffi", "string_to_binary")
fn string_to_binary(s: String) -> BitArray

pub type Token {
  Symbol(String)
  IntVal(Int)
  LParen
  RParen
}
pub type TokenInfo { TokenInfo(token: Token, line: Int, col: Int) }
pub type ParseError { ParseError(message: String, line: Int, col: Int) }

pub fn tokenize(input: String) -> List(TokenInfo) {
  do_tokenize(string.to_graphemes(input), "", 1, 1, 1, 1)
}
fn do_tokenize(chars, acc, sl, sc, l, c) {
  case chars {
    [] -> flush_token(acc, sl, sc, [])
    ["\n", ..rest] -> flush_token(acc, sl, sc, do_tokenize(rest, "", 1, 1, l + 1, 1))
    [" ", ..rest] | ["\t", ..rest] -> flush_token(acc, sl, sc, do_tokenize(rest, "", 1, 1, l, c + 1))
    ["(", ..rest] -> flush_token(acc, sl, sc, [TokenInfo(LParen, l, c), ..do_tokenize(rest, "", 1, 1, l, c + 1)])
    [")", ..rest] -> flush_token(acc, sl, sc, [TokenInfo(RParen, l, c), ..do_tokenize(rest, "", 1, 1, l, c + 1)])
    [ch, ..rest] -> {
      let #(nsl, nsc) = case acc {
        "" -> #(l, c)
        _ -> #(sl, sc)
      }
      do_tokenize(rest, acc <> ch, nsl, nsc, l, c + 1)
    }
  }
}
fn flush_token(acc, l, c, tail) {
  case acc {
    "" -> tail
    _ -> case int.parse(acc) {
      Ok(n) -> [TokenInfo(IntVal(n), l, c), ..tail]
      Error(_) -> [TokenInfo(Symbol(acc), l, c), ..tail]
    }
  }
}

pub type SExpr {
  SAtom(Token, line: Int, col: Int)
  SListExpr(List(SExpr), line: Int, col: Int)
}
pub fn parse_sexpr(tokens: List(TokenInfo)) -> Result(#(SExpr, List(TokenInfo)), ParseError) {
  case tokens {
    [] -> Error(ParseError("Unexpected EOF", 1, 1))
    [TokenInfo(LParen, l, c), ..rest] -> {
      use #(exprs, rest2) <- result.try(parse_list(rest, []))
      Ok(#(SListExpr(exprs, l, c), rest2))
    }
    [TokenInfo(RParen, l, c), ..] -> Error(ParseError("Unexpected )", l, c))
    [TokenInfo(other, l, c), ..rest] -> Ok(#(SAtom(other, l, c), rest))
  }
}
fn parse_list(tokens, acc) {
  case tokens {
    [] -> Error(ParseError("Unclosed (", 1, 1))
    [TokenInfo(RParen, _, _), ..rest] -> Ok(#(list.reverse(acc), rest))
    _ -> {
      use #(expr, rest) <- result.try(parse_sexpr(tokens))
      parse_list(rest, [expr, ..acc])
    }
  }
}

pub fn sexpr_to_term(sexpr: SExpr) -> Result(SurfaceTerm, ParseError) {
  case sexpr {
    SAtom(IntVal(n), _, _) -> Ok(SInt(n))
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
        [SAtom(Symbol("do"), _, _), SAtom(Symbol(ab), _, _), SAtom(Symbol(op), _, _), ..args] -> {
          use parsed_args <- result.try(list.try_map(args, sexpr_to_term))
          Ok(elab_types.SDo(ab, op, parsed_args))
        }
        [SAtom(Symbol("handle"), _, _), comp, handler, SAtom(Symbol(ab), _, _)] -> {
          use comp_t <- result.try(sexpr_to_term(comp))
          use handler_t <- result.try(sexpr_to_term(handler))
          Ok(elab_types.SHandle(comp_t, handler_t, ab))
        }
        [SAtom(Symbol("list"), _, _), ..rest] -> {
          case list.try_map(rest, sexpr_to_term) {
            Ok(terms) -> Ok(SList(terms))
            Error(e) -> Error(e)
          }
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

pub fn parse_string(input: String) -> Result(SurfaceTerm, ParseError) {
  case parse_sexpr(tokenize(input)) {
    Ok(#(sexpr, [])) -> sexpr_to_term(sexpr)
    Ok(#(_, [TokenInfo(_, l, c), ..])) -> Error(ParseError("Extra tokens after expression", l, c))
    Error(e) -> Error(e)
  }
}
