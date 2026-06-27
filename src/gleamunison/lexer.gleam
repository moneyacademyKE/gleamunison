import gleam/float
import gleam/int
import gleam/string

pub type Token {
  Symbol(String)
  IntVal(Int)
  FloatVal(Float)
  LParen
  RParen
  Quote
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

fn do_tokenize(chars, acc, sl, sc, l, c) {
  case chars {
    [] -> flush_token(acc, sl, sc, [])
    ["\n", ..rest] ->
      flush_token(acc, sl, sc, do_tokenize(rest, "", 1, 1, l + 1, 1))
    [" ", ..rest] | ["\t", ..rest] ->
      flush_token(acc, sl, sc, do_tokenize(rest, "", 1, 1, l, c + 1))
    ["(", ..rest] ->
      flush_token(acc, sl, sc, [
        TokenInfo(LParen, l, c),
        ..do_tokenize(rest, "", 1, 1, l, c + 1)
      ])
    [")", ..rest] ->
      flush_token(acc, sl, sc, [
        TokenInfo(RParen, l, c),
        ..do_tokenize(rest, "", 1, 1, l, c + 1)
      ])
    [";", ..rest] -> flush_token(acc, sl, sc, skip_line(rest, l, c + 1))
    ["'", ..rest] ->
      flush_token(acc, sl, sc, [
        TokenInfo(Quote, l, c),
        ..do_tokenize(rest, "", sl, sc, l, c + 1)
      ])
    ["\"", ..rest] -> {
      case acc {
        "" -> read_string(rest, "\"", l, c, l, c + 1)
        _ -> do_tokenize(rest, acc <> "\"", sl, sc, l, c + 1)
      }
    }
    [ch, ..rest] -> {
      let #(nsl, nsc) = case acc {
        "" -> #(l, c)
        _ -> #(sl, sc)
      }
      do_tokenize(rest, acc <> ch, nsl, nsc, l, c + 1)
    }
  }
}

fn read_string(chars, acc, sl, sc, l, c) {
  case chars {
    [] -> [TokenInfo(Symbol(acc <> "\""), sl, sc)]
    ["\n", ..rest] -> read_string(rest, acc <> "\n", sl, sc, l + 1, 1)
    ["\\", "\"", ..rest] -> read_string(rest, acc <> "\"", sl, sc, l, c + 2)
    ["\\", "n", ..rest] -> read_string(rest, acc <> "\n", sl, sc, l, c + 2)
    ["\\", "\\", ..rest] -> read_string(rest, acc <> "\\", sl, sc, l, c + 2)
    ["\"", ..rest] ->
      flush_token(acc <> "\"", sl, sc, do_tokenize(rest, "", 1, 1, l, c + 1))
    [ch, ..rest] -> read_string(rest, acc <> ch, sl, sc, l, c + 1)
  }
}

fn skip_line(chars, l, c) {
  case chars {
    [] -> []
    ["\n", ..rest] -> do_tokenize(rest, "", 1, 1, l + 1, 1)
    [_, ..rest] -> skip_line(rest, l, c + 1)
  }
}

fn flush_token(acc, l, c, tail) {
  case acc {
    "" -> tail
    _ ->
      case int.parse(acc) {
        Ok(n) -> [TokenInfo(IntVal(n), l, c), ..tail]
        Error(_) ->
          case float.parse(acc) {
            Ok(f) -> [TokenInfo(FloatVal(f), l, c), ..tail]
            Error(_) -> [TokenInfo(Symbol(acc), l, c), ..tail]
          }
      }
  }
}
