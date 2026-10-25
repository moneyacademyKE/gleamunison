//// Opinionated formatter for gleamunison surface syntax (roadmap 9.2).
////
//// One rule, no configuration:
////   - a form is flat when it fits in 72 columns at its indent;
////   - otherwise it breaks after its head, children one per line at +2;
////   - when the head is an atom, the first child joins the opening line
////     if it fits flat (the `(define name …)` convention).
////
//// Formatting is a pure function of the parse tree, so it is idempotent by
//// construction. Comments are data, not casualties: a comment before a form
//// stays before it, a comment on a form's line trails that line, and a comment
//// written inside a form stays inside it, on the line above the child that
//// followed it. A comment inside a form forces that form to break, because
//// flat text has nowhere to put one and dropping it is not an option.
//// 'x prints as (quote x).

import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleamunison/lexer.{
  type ParseError, type Token, type TokenInfo, Comment, FloatVal, IntVal, LParen,
  RParen, Symbol, TokenInfo,
}
import gleamunison/parser.{type SExpr, SAtom, SListExpr}
import gleamunison/verify

const max_width = 72

/// A source position: line, then column.
type Pos =
  #(Int, Int)

/// Where every list form ends, keyed by where it opens. A list's span is not
/// derivable from its children — the last child ends before the closer — and
/// that difference decides whether a comment sits inside a form or after it.
type Closers =
  Dict(Pos, Pos)

/// A source comment with its original position, kept in source order.
type Cmt {
  Cmt(text: String, line: Int, col: Int)
}

/// A child's comments, attributed by position: `before` its first line,
/// `inside` its span, or `trailing` its first line.
type Placed {
  Placed(before: List(Cmt), inside: List(Cmt), trailing: Option(Cmt))
}

/// Format a whole source file: every top-level form on its own line(s),
/// forms separated by single newlines, comments preserved in place, trailing
/// newline at the end.
pub fn format_source(src: String) -> Result(String, ParseError) {
  let tokens = lexer.tokenize(src)
  let comments = collect_comments(tokens)
  let code = parser.drop_comments(tokens)
  use exprs <- result.try(verify.parse_all_sexprs(code, []))
  let closers = closer_positions(code)
  case exprs, comments {
    [], [] -> Ok("")
    _, _ ->
      Ok(merge(comments, exprs, closers) |> string.join("\n")) |> append_nl
  }
}

fn append_nl(r: Result(String, ParseError)) -> Result(String, ParseError) {
  result.map(r, fn(s) { s <> "\n" })
}

fn collect_comments(tokens: List(TokenInfo)) -> List(Cmt) {
  list.filter_map(tokens, fn(t) {
    case t {
      TokenInfo(Comment(text), line, col) -> Ok(Cmt(text, line, col))
      _ -> Error(Nil)
    }
  })
}

fn closer_positions(tokens: List(TokenInfo)) -> Closers {
  scan_closers(tokens, [], dict.new())
}

fn scan_closers(
  tokens: List(TokenInfo),
  open: List(Pos),
  acc: Closers,
) -> Closers {
  case tokens {
    [] -> acc
    [TokenInfo(LParen, line, col), ..rest] ->
      scan_closers(rest, [#(line, col), ..open], acc)
    [TokenInfo(RParen, line, col), ..rest] ->
      case open {
        [start, ..outer] ->
          scan_closers(rest, outer, dict.insert(acc, start, #(line, col)))
        // A closer with nothing open is a parse error, reported by the parser
        // rather than guessed at here.
        [] -> scan_closers(rest, [], acc)
      }
    [_, ..rest] -> scan_closers(rest, open, acc)
  }
}

fn start_of(e: SExpr) -> Pos {
  case e {
    SAtom(_, line, col) -> #(line, col)
    SListExpr(_, line, col) -> #(line, col)
  }
}

/// The position a form ends at: a list ends at its closing paren. The
/// synthetic `(quote x)` a `'x` becomes has no paren of its own, so it ends
/// where the quoted form does.
fn end_of(e: SExpr, closers: Closers) -> Pos {
  case e {
    SAtom(_, line, col) -> #(line, col)
    SListExpr(items, line, col) ->
      case dict.get(closers, #(line, col)) {
        Ok(end) -> end
        Error(_) ->
          case list.last(items) {
            Ok(last) -> end_of(last, closers)
            Error(_) -> #(line, col)
          }
      }
  }
}

/// Strictly before a position, in reading order.
fn before_pos(c: Cmt, pos: Pos) -> Bool {
  c.line < pos.0 || { c.line == pos.0 && c.col < pos.1 }
}

/// Interleave comments and rendered forms into output lines.
fn merge(
  comments: List(Cmt),
  exprs: List(SExpr),
  closers: Closers,
) -> List(String) {
  case exprs {
    [] -> list.map(comments, fn(c) { c.text })
    [e, ..rest] -> {
      let start = start_of(e)
      let end = end_of(e, closers)
      let #(before, rest1) =
        list.partition(comments, fn(c) { before_pos(c, start) })
      // A comment on the form's first line trails it; so does one after the
      // closer, when the closer has a line to itself. Neither belongs to the
      // next form.
      let #(trailing, rest2) =
        list.partition(rest1, fn(c) {
          c.line == start.0 || { c.line == end.0 && c.col > end.1 }
        })
      let #(inside, after) = list.partition(rest2, fn(c) { before_pos(c, end) })
      let body = render(e, 0, inside, closers)
      let body = case trailing {
        [c, ..] -> append_to_first_line(body, c.text)
        [] -> body
      }
      list.append(list.map(before, fn(c) { c.text }), [body])
      |> list.append(merge(after, rest, closers))
    }
  }
}

fn render(
  e: SExpr,
  indent: Int,
  comments: List(Cmt),
  closers: Closers,
) -> String {
  case e {
    SAtom(tok, _, _) -> token_text(tok)
    SListExpr(items, _, _) -> {
      let flat = flat_text(e)
      case comments {
        // A comment has nowhere to live in flat text, so any comment inside
        // this form breaks it.
        [] ->
          case indent + string.length(flat) <= max_width {
            True -> flat
            False -> break_list(items, indent, [], closers)
          }
        _ -> break_list(items, indent, comments, closers)
      }
    }
  }
}

fn break_list(
  items: List(SExpr),
  indent: Int,
  comments: List(Cmt),
  closers: Closers,
) -> String {
  case items {
    [] -> "()"
    [first, ..rest] -> {
      let #(placed, remaining) = place(comments, first, closers)
      // A comment can only precede the first child when the source put a line
      // break straight after the opening paren. It stays where it was written:
      // under the paren, with the head below it.
      let #(opening, head_inline) = case placed.before {
        [] -> #(
          "("
            <> append_trailing(
            render(first, indent + 1, placed.inside, closers),
            placed.trailing,
          ),
          True,
        )
        above -> #(
          "("
            <> string.concat(
            list.map(above, fn(c) { "\n" <> pad(indent + 2) <> c.text }),
          )
            <> "\n"
            <> pad(indent + 2)
            <> append_trailing(
            render(first, indent + 2, placed.inside, closers),
            placed.trailing,
          ),
          False,
        )
      }
      // The `(define name …)` convention: when the head is an atom and the
      // first child fits flat on the opening line, keep them together. A child
      // carrying a comment needs lines of its own, so it stays out.
      let #(opening, remaining, rest) = case first, rest {
        SAtom(_, _, _), [second, ..tail] -> {
          let #(next, after) = place(remaining, second, closers)
          let flat2 = flat_text(second)
          let fits =
            indent + string.length(opening) + 1 + string.length(flat2)
            <= max_width
          let clean =
            next.before == [] && next.inside == [] && next.trailing == None
          case head_inline && fits && clean {
            True -> #(opening <> " " <> flat2, after, tail)
            False -> #(opening, remaining, rest)
          }
        }
        _, _ -> #(opening, remaining, rest)
      }
      let #(lines, leftover) = place_children(rest, indent, remaining, closers)
      // Comments after the last child are still inside the form: they go above
      // the closer, which then needs a line of its own.
      let closing = case leftover {
        [] -> ")"
        cs ->
          string.concat(
            list.map(cs, fn(c) { "\n" <> pad(indent + 2) <> c.text }),
          )
          <> "\n"
          <> pad(indent)
          <> ")"
      }
      opening <> string.concat(lines) <> closing
    }
  }
}

fn place_children(
  children: List(SExpr),
  indent: Int,
  comments: List(Cmt),
  closers: Closers,
) -> #(List(String), List(Cmt)) {
  list.fold(children, #([], comments), fn(acc, child) {
    let #(lines, pending) = acc
    let #(placed, later) = place(pending, child, closers)
    let text =
      render(child, indent + 2, placed.inside, closers)
      |> append_trailing(placed.trailing)
    let above =
      list.map(placed.before, fn(c) { "\n" <> pad(indent + 2) <> c.text })
    #(
      list.append(lines, list.append(above, ["\n" <> pad(indent + 2) <> text])),
      later,
    )
  })
}

/// Attribute the comments around one child, returning what belongs after it.
/// Comments and children are both in source order, so one left-to-right pass
/// places every comment exactly once.
fn place(
  comments: List(Cmt),
  child: SExpr,
  closers: Closers,
) -> #(Placed, List(Cmt)) {
  let start = start_of(child)
  let end = end_of(child, closers)
  let #(mine, later) = list.partition(comments, fn(c) { before_pos(c, end) })
  let #(on_start, rest) = list.partition(mine, fn(c) { c.line == start.0 })
  let #(before, inside) = list.partition(rest, fn(c) { c.line < start.0 })
  let trailing = case on_start {
    [c, ..] -> Some(c)
    [] -> None
  }
  #(Placed(before: before, inside: inside, trailing: trailing), later)
}

fn append_trailing(body: String, trailing: Option(Cmt)) -> String {
  case trailing {
    Some(c) -> append_to_first_line(body, c.text)
    None -> body
  }
}

fn append_to_first_line(body: String, text: String) -> String {
  case string.split(body, "\n") {
    [first, ..rest] -> string.join([first <> " " <> text, ..rest], "\n")
    [] -> body <> " " <> text
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
