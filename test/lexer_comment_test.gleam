import gleam/list
import gleam/string
import gleamunison/lexer.{Comment, IntVal, Symbol, TokenInfo, tokenize}
import gleamunison/parser
import gleamunison/verify

pub fn full_line_comment_becomes_a_token_test() {
  let toks = tokenize("; hello\n42")
  case toks {
    [TokenInfo(Comment(text), 1, 1), TokenInfo(IntVal(42), 2, 1)] ->
      case text == "; hello" {
        True -> Nil
        False -> panic as "comment text should include the semicolon"
      }
    _ -> panic as "expected comment token at 1:1 then 42 at 2:1"
  }
}

pub fn trailing_comment_keeps_its_position_test() {
  // ( f x ) occupies cols 1-5, the semicolon is at col 7
  let toks = tokenize("(f x) ; note\n")
  let last = list_last(toks)
  case last {
    TokenInfo(Comment("; note"), 1, 7) -> Nil
    _ -> panic as "trailing comment should be at 1:7 with its text"
  }
}

pub fn semicolon_inside_a_string_is_not_a_comment_test() {
  let toks = tokenize("\"a;b\"")
  case toks {
    [TokenInfo(Symbol(s), _, _)] ->
      case string.contains(s, ";") {
        True -> Nil
        False -> panic as "string lost its semicolon"
      }
    _ -> panic as "expected a single string token, no comment token"
  }
}

pub fn parser_ignores_comments_everywhere_test() {
  // Same program, with and without comments. Trees can only differ in
  // positions (comments shift them legitimately), so compare structure
  // with positions stripped.
  let assert Ok(a) = verify.parse_all_sexprs(tokenize("(add 1 2)"), [])
  let assert Ok(b) =
    verify.parse_all_sexprs(
      tokenize("; lead\n(add ; inside\n 1 2) ; trail\n; eof"),
      [],
    )
  case list.map(a, norm) == list.map(b, norm) {
    True -> Nil
    False -> panic as "comments changed the parse"
  }
}

fn norm(e: parser.SExpr) -> String {
  case e {
    parser.SAtom(tok, _, _) -> string.inspect(tok)
    parser.SListExpr(items, _, _) ->
      "(" <> { items |> list.map(norm) |> string.join(" ") } <> ")"
  }
}

pub fn comment_only_source_parses_to_nothing_test() {
  let assert Ok(exprs) = verify.parse_all_sexprs(tokenize("; a\n; b\n"), [])
  case exprs {
    [] -> Nil
    _ -> panic as "comment-only source should produce zero exprs"
  }
}

fn list_last(xs: List(a)) -> a {
  case xs {
    [x] -> x
    [_, ..rest] -> list_last(rest)
    [] -> panic as "empty list"
  }
}
