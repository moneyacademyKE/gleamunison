//// Opinionated formatter for gleamunison surface syntax (roadmap 9.2).
////
//// One rule, no configuration:
////   - a form is flat when it fits in 72 columns at its indent;
////   - otherwise it breaks after its head, children one per line at +2;
////   - when the head is an atom, the first child joins the opening line
////     if it fits flat (the `(define name …)` convention).
////
//// Formatting is a pure function of the parse tree, so it is idempotent
//// by construction. Comments are data, not casualties: full-line comments
//// stay before their form, a trailing comment joins its form's first
//// line, and a comment inside a form hoists above the form (documented
//// approximation — never dropped). 'x prints as (quote x).

import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleamunison/lexer.{
  type ParseError, type Token, type TokenInfo, Comment, FloatVal, IntVal, Symbol,
  TokenInfo,
}
import gleamunison/parser.{type SExpr, SAtom, SListExpr}
import gleamunison/verify

const max_width = 72

/// A source comment with its original line, kept in source order.
type Cmt {
  Cmt(text: String, line: Int)
}

/// Format a whole source file: every top-level form on its own line(s),
/// forms separated by single newlines, comments preserved (see module
/// docs), trailing newline at the end.
pub fn format_source(src: String) -> Result(String, ParseError) {
  let tokens = lexer.tokenize(src)
  let comments = collect_comments(tokens)
  let code = parser.drop_comments(tokens)
  use exprs <- result.try(verify.parse_all_sexprs(code, []))
  case exprs, comments {
    [], [] -> Ok("")
    _, _ -> Ok(merge(comments, exprs) |> string.join("\n")) |> append_nl
  }
}

fn append_nl(r: Result(String, ParseError)) -> Result(String, ParseError) {
  result.map(r, fn(s) { s <> "\n" })
}

fn collect_comments(tokens: List(TokenInfo)) -> List(Cmt) {
  list.filter_map(tokens, fn(t) {
    case t {
      TokenInfo(Comment(text), line, _) -> Ok(Cmt(text, line))
      _ -> Error(Nil)
    }
  })
}

fn start_line(e: SExpr) -> Int {
  case e {
    SAtom(_, l, _) -> l
    SListExpr(_, l, _) -> l
  }
}

/// Approximate end line: the line of the last atom inside the form. After
/// one format pass this is exact (the closer hugs the last child).
fn end_line(e: SExpr) -> Int {
  case e {
    SAtom(_, l, _) -> l
    SListExpr(items, l, _) ->
      case list.last(items) {
        Ok(last) -> end_line(last)
        Error(_) -> l
      }
  }
}

/// Interleave comments and rendered forms into output lines.
fn merge(comments: List(Cmt), exprs: List(SExpr)) -> List(String) {
  case exprs {
    [] -> list.map(comments, fn(c) { c.text })
    [e, ..rest] -> {
      let s = start_line(e)
      let en = end_line(e)
      // A comment on the form's own line trails it.
      let #(trailing, others) = list.partition(comments, fn(c) { c.line == s })
      // Comments up to this form's end belong before it (preceding or
      // hoisted interior).
      let #(before, after) = list.partition(others, fn(c) { c.line <= en })
      let body = render_top(e)
      let body = case trailing {
        [c, ..] -> append_to_first_line(body, c.text)
        [] -> body
      }
      list.append(list.map(before, fn(c) { c.text }), [body])
      |> list.append(merge(after, rest))
    }
  }
}

fn append_to_first_line(body: String, text: String) -> String {
  case string.split(body, "\n") {
    [first, ..rest] -> string.join([first <> " " <> text, ..rest], "\n")
    [] -> body <> " " <> text
  }
}

fn render_top(e: SExpr) -> String {
  render(e, 0)
}

fn render(e: SExpr, indent: Int) -> String {
  case e {
    SAtom(tok, _, _) -> token_text(tok)
    SListExpr(items, _, _) -> {
      let flat = flat_text(e)
      case indent + string.length(flat) <= max_width {
        True -> flat
        False -> break_list(items, indent)
      }
    }
  }
}

fn break_list(items: List(SExpr), indent: Int) -> String {
  case items {
    [] -> "()"
    [first, ..rest] -> {
      let line0 = "(" <> render(first, indent + 1)
      // The `(define name …)` convention: when the head is an atom and the
      // first child fits flat on the opening line, keep them together.
      let #(line, remaining) = case first, rest {
        SAtom(_, _, _), [second, ..tail] -> {
          let flat2 = flat_text(second)
          case
            indent + string.length(line0) + 1 + string.length(flat2)
            <= max_width
          {
            True -> #(line0 <> " " <> flat2, tail)
            False -> #(line0, rest)
          }
        }
        _, _ -> #(line0, rest)
      }
      let body =
        remaining
        |> list.map(fn(el) { "\n" <> pad(indent + 2) <> render(el, indent + 2) })
        |> string.concat
      line <> body <> ")"
    }
  }
}

fn flat_text(e: SExpr) -> String {
  case e {
    SAtom(tok, _, _) -> token_text(tok)
    SListExpr(items, _, _) ->
      "(" <> { items |> list.map(flat_text) |> string.join(" ") } <> ")"
  }
}

fn token_text(tok: Token) -> String {
  case tok {
    Symbol(s) -> s
    IntVal(n) -> int.to_string(n)
    FloatVal(f) -> float.to_string(f)
    // LParen/RParen/Quote never appear as list elements: parse_sexpr has
    // already structured them. UnterminatedString fails tokenize→parse.
    _ -> ""
  }
}

fn pad(n: Int) -> String {
  string.repeat(" ", n)
}
