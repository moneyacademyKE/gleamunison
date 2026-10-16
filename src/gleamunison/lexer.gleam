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
  UnterminatedString(String)
  /// A `;` comment, text preserved including the leading semicolon.
  /// Emitted only outside string literals (strings scan in their own
  /// loop, so a `;` inside quotes is string content by construction).
  /// The parser treats comments as whitespace; the formatter reattaches
  /// them. Nothing is ever silently dropped.
  Comment(String)
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
    [";", ..rest] ->
      flush_token(acc, sl, sc, read_comment(rest, ";", l, c, l, c + 1))
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
    [] -> [TokenInfo(UnterminatedString(acc), sl, sc)]
    ["\n", ..rest] -> read_string(rest, acc <> "\n", sl, sc, l + 1, 1)
    ["\\", "\"", ..rest] -> read_string(rest, acc <> "\"", sl, sc, l, c + 2)
    ["\\", "n", ..rest] -> read_string(rest, acc <> "\n", sl, sc, l, c + 2)
    ["\\", "\\", ..rest] -> read_string(rest, acc <> "\\", sl, sc, l, c + 2)
    ["\"", ..rest] ->
      flush_token(acc <> "\"", sl, sc, do_tokenize(rest, "", 1, 1, l, c + 1))
    [ch, ..rest] -> read_string(rest, acc <> ch, sl, sc, l, c + 1)
  }
}

fn read_comment(chars, acc, sl, sc, l, c) {
  case chars {
    [] -> [TokenInfo(Comment(acc), sl, sc)]
    ["\n", ..rest] -> [
      TokenInfo(Comment(acc), sl, sc),
      ..do_tokenize(rest, "", 1, 1, l + 1, 1)
    ]
    [ch, ..rest] -> read_comment(rest, acc <> ch, sl, sc, l, c + 1)
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
