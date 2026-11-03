import gleam/float
import gleam/int
import gleam/string
import gleamunison/source_budget

pub type Token {
  Symbol(String)
  IntVal(Int)
  FloatVal(Float)
  LParen
  RParen
  Quote
  AdmissionRefused(String)
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

/// Render a parse error as a sentence: the message with its position.
/// Callers add their own prefix; this owns only the shared tail so the
/// position is never rendered with inspects or re-spelled per site.
pub fn describe_error(error: ParseError) -> String {
  error.message
  <> " at line "
  <> int.to_string(error.line)
  <> ", col "
  <> int.to_string(error.col)
}

pub fn tokenize(input: String) -> List(TokenInfo) {
  case source_budget.check(input) {
    Error(reason) -> [TokenInfo(AdmissionRefused(reason), 1, 1)]
    Ok(_) -> do_tokenize(string.to_graphemes(input), "", 1, 1, 1, 1)
  }
}

fn do_tokenize(chars, acc, sl, sc, l, c) {
  case chars {
    [] -> flush_token(acc, sl, sc, [])
    // CRLF is a single grapheme cluster in Unicode, so it arrives as one
    // element here. Matching it before the `\n` clause is what makes a file
    // with Windows line endings the same program as the same file with LF.
    ["\r\n", ..rest] ->
      flush_token(acc, sl, sc, do_tokenize(rest, "", 1, 1, l + 1, 1))
    ["\n", ..rest] ->
      flush_token(acc, sl, sc, do_tokenize(rest, "", 1, 1, l + 1, 1))
    [" ", ..rest] | ["\t", ..rest] | ["\r", ..rest] ->
      // `\r` is a line break, not a symbol byte. Skipping it here means a CRLF
      // file parses exactly like the same file with LF endings; the following
      // `\n` still advances the line counter.
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
    // CRLF is one grapheme cluster, so a comment that only terminates on "\n"
    // never terminates in a Windows-authored file: it swallows the rest of the
    // source and the parser reports "Unexpected EOF" on a good program. The
    // main tokenizer already treats both endings as one line break; a comment
    // ends where the line does.
    ["\r\n", ..rest] -> [
      TokenInfo(Comment(acc), sl, sc),
      ..do_tokenize(rest, "", 1, 1, l + 1, 1)
    ]
    ["\n", ..rest] -> [
      TokenInfo(Comment(acc), sl, sc),
      ..do_tokenize(rest, "", 1, 1, l + 1, 1)
    ]
    // A lone CR is whitespace without a line break, exactly as the main loop
    // treats it: the comment ends and the CR is skipped.
    ["\r", ..rest] -> [
      TokenInfo(Comment(acc), sl, sc),
      ..do_tokenize(rest, "", 1, 1, l, c)
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
