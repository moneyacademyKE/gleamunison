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

pub fn tokenize(input: String) -> List(Token) {
  let chars = string.to_graphemes(input)
  do_tokenize(chars, "")
}

fn do_tokenize(chars: List(String), acc: String) -> List(Token) {
  case chars {
    [] -> flush_token(acc, [])
    [" ", ..rest] | ["\n", ..rest] | ["\t", ..rest] ->
      flush_token(acc, do_tokenize(rest, ""))
    ["(", ..rest] ->
      flush_token(acc, [LParen, ..do_tokenize(rest, "")])
    [")", ..rest] ->
      flush_token(acc, [RParen, ..do_tokenize(rest, "")])
    [c, ..rest] ->
      do_tokenize(rest, acc <> c)
  }
}

fn flush_token(acc: String, tail: List(Token)) -> List(Token) {
  case acc {
    "" -> tail
    _ -> {
      case int.parse(acc) {
        Ok(n) -> [IntVal(n), ..tail]
        Error(_) -> [Symbol(acc), ..tail]
      }
    }
  }
}

pub type SExpr {
  SAtom(Token)
  SListExpr(List(SExpr))
}

pub fn parse_sexpr(tokens: List(Token)) -> Result(#(SExpr, List(Token)), String) {
  case tokens {
    [] -> Error("Unexpected EOF")
    [LParen, ..rest] -> {
      use #(exprs, rest2) <- result.try(parse_list(rest, []))
      Ok(#(SListExpr(exprs), rest2))
    }
    [RParen, ..] -> Error("Unexpected )")
    [other, ..rest] -> Ok(#(SAtom(other), rest))
  }
}

fn parse_list(tokens: List(Token), acc: List(SExpr)) -> Result(#(List(SExpr), List(Token)), String) {
  case tokens {
    [] -> Error("Unclosed (")
    [RParen, ..rest] -> Ok(#(list.reverse(acc), rest))
    _ -> {
      use #(expr, rest) <- result.try(parse_sexpr(tokens))
      parse_list(rest, [expr, ..acc])
    }
  }
}

pub fn sexpr_to_term(sexpr: SExpr) -> Result(SurfaceTerm, String) {
  case sexpr {
    SAtom(IntVal(n)) -> Ok(SInt(n))
    SAtom(Symbol(name)) -> Ok(SVar(name))
    SAtom(_) -> Error("Invalid atom")
    SListExpr(exprs) -> {
      case exprs {
        [SAtom(Symbol("let")), SAtom(Symbol(name)), val, body] -> {
          use val_t <- result.try(sexpr_to_term(val))
          use body_t <- result.try(sexpr_to_term(body))
          Ok(SLet(name, val_t, body_t))
        }
        [SAtom(Symbol("lam")), SAtom(Symbol(name)), body] -> {
          use body_t <- result.try(sexpr_to_term(body))
          Ok(SLambda(name, body_t))
        }
        _ -> {
          use terms <- result.try(list.try_map(exprs, sexpr_to_term))
          Ok(SList(terms))
        }
      }
    }
  }
}

pub fn parse_string(input: String) -> Result(SurfaceTerm, String) {
  case parse_sexpr(tokenize(input)) {
    Ok(#(sexpr, [])) -> sexpr_to_term(sexpr)
    Ok(#(_, _)) -> Error("Extra tokens after expression")
    Error(e) -> Error(e)
  }
}
