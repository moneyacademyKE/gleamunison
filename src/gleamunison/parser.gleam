import gleam/list
import gleam/string
import gleam/int
import gleam/result
import gleamunison/elab_types.{type SurfaceTerm, SInt, SVar, SLet, SLambda, SList}

pub type Token {
  Symbol(String)
  IntVal(Int)
  LParen
  RParen
}

pub type TokenInfo {
  TokenInfo(token: Token, line: Int, col: Int)
}

pub type ParseError {
  ParseError(message: String, line: Int, col: Int)
}

pub fn tokenize(input: String) -> List(TokenInfo) {
  do_tokenize(string.to_graphemes(input), "", 1, 1, 1, 1)
}

fn do_tokenize(chars: List(String), acc: String, sl: Int, sc: Int, l: Int, c: Int) -> List(TokenInfo) {
  case chars {
    [] -> flush_token(acc, sl, sc, [])
    ["\n", ..rest] ->
      flush_token(acc, sl, sc, do_tokenize(rest, "", 1, 1, l + 1, 1))
    [" ", ..rest] | ["\t", ..rest] ->
      flush_token(acc, sl, sc, do_tokenize(rest, "", 1, 1, l, c + 1))
    ["(", ..rest] ->
      flush_token(acc, sl, sc, [TokenInfo(LParen, l, c), ..do_tokenize(rest, "", 1, 1, l, c + 1)])
    [")", ..rest] ->
      flush_token(acc, sl, sc, [TokenInfo(RParen, l, c), ..do_tokenize(rest, "", 1, 1, l, c + 1)])
    [ch, ..rest] -> {
      let #(nsl, nsc) = case acc {
        "" -> #(l, c)
        _ -> #(sl, sc)
      }
      do_tokenize(rest, acc <> ch, nsl, nsc, l, c + 1)
    }
  }
}

fn flush_token(acc: String, l: Int, c: Int, tail: List(TokenInfo)) -> List(TokenInfo) {
  case acc {
    "" -> tail
    _ -> {
      case int.parse(acc) {
        Ok(n) -> [TokenInfo(IntVal(n), l, c), ..tail]
        Error(_) -> [TokenInfo(Symbol(acc), l, c), ..tail]
      }
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

fn parse_list(tokens: List(TokenInfo), acc: List(SExpr)) -> Result(#(List(SExpr), List(TokenInfo)), ParseError) {
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
    SAtom(Symbol(name), _, _) -> Ok(SVar(name))
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
        _ -> {
          case list.try_map(exprs, sexpr_to_term) {
            Ok(terms) -> Ok(SList(terms))
            Error(e) -> Error(e)
          }
        }
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
