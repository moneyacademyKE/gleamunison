//// Opinionated formatter for gleamunison surface syntax (roadmap 9.2).
////
//// One rule, no configuration:
////   - a form is flat when it fits in 72 columns at its indent;
////   - otherwise it breaks after its head, children one per line at +2;
////   - when the head is an atom, the first child joins the opening line
////     if it fits flat (the `(define name …)` convention).
////
//// Formatting is a pure function of the parse tree, so it is idempotent
//// by construction. Known normalizations: `;` comments are dropped (the
//// lexer discards them before layout), and 'x prints as (quote x).

import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleamunison/lexer.{type ParseError, type Token, FloatVal, IntVal, Symbol}
import gleamunison/parser.{type SExpr, SAtom, SListExpr}
import gleamunison/verify

const max_width = 72

/// Format a whole source file: every top-level form on its own line(s),
/// forms separated by single newlines, trailing newline at the end.
pub fn format_source(src: String) -> Result(String, ParseError) {
  let tokens = lexer.tokenize(src)
  use exprs <- result.try(verify.parse_all_sexprs(tokens, []))
  case exprs {
    [] -> Ok("")
    _ ->
      Ok(
        exprs
        |> list.map(render_top)
        |> string.join("\n")
        <> "\n",
      )
  }
}

/// True when the source carries `;` comments the formatter will drop —
/// callers surface this as a warning, never silently.
pub fn drops_comments(src: String) -> Bool {
  string.contains(src, ";")
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
