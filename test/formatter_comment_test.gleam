import gleam/string
import gleamunison/formatter

pub fn full_line_comment_stays_before_its_form_test() {
  let src = "; the answer\n(define answer 42)\n"
  let assert Ok(out) = formatter.format_source(src)
  case out == "; the answer\n(define answer 42)\n" {
    True -> Nil
    False -> panic as { "full-line comment moved or dropped:\n" <> out }
  }
}

pub fn trailing_comment_joins_the_forms_first_line_test() {
  let src = "(define answer 42) ; the answer\n"
  let assert Ok(out) = formatter.format_source(src)
  case out == "(define answer 42) ; the answer\n" {
    True -> Nil
    False -> panic as { "trailing comment lost:\n" <> out }
  }
}

pub fn trailing_comment_survives_a_broken_form_test() {
  // Too long to stay flat: it breaks, and the comment stays on the line
  // that holds the closer — where re-reading the output finds it trailing.
  let src =
    "(define some-rather-long-function-name-here (lam some-argument-name (add some-argument-name 1000))) ; doc\n"
  let assert Ok(out) = formatter.format_source(src)
  case string.ends_with(string.trim_end(out), "; doc") {
    True -> Nil
    False -> panic as { "trailing comment not after the closer:\n" <> out }
  }
}

/// Formatting is a fixed point: a trailing comment written where re-reading
/// finds it trailing. Appending it to a broken form's first line put it
/// *inside* the form on the next pass, which then moved it again.
pub fn a_broken_forms_trailing_comment_is_idempotent_test() {
  let src =
    "(define (long-name alpha beta gamma delta)\n  (chain ((a alpha) (b beta) (c gamma)) (add a b))) ; why\n(define two 2)\n"
  let assert Ok(once) = formatter.format_source(src)
  let assert Ok(twice) = formatter.format_source(once)
  case twice == once {
    True -> Nil
    False -> panic as { "not idempotent:\n" <> once <> "\n---\n" <> twice }
  }
}

/// A comment written inside a form describes the child that follows it, so it
/// stays inside: hoisting it above the form moved it away from what it
/// documents and, for a form that then fit on one line, out of the form
/// entirely.
pub fn interior_comment_stays_inside_the_form_test() {
  let src = "(define answer\n  ; the meaning of life\n  42)\n"
  let assert Ok(out) = formatter.format_source(src)
  case out == "(define answer\n  ; the meaning of life\n  42)\n" {
    True -> Nil
    False -> panic as { "interior comment not kept in place:\n" <> out }
  }
}

/// A short form with a comment inside cannot be flat: flat text has nowhere to
/// put a comment, and dropping it is not an option.
pub fn interior_comment_forces_a_break_test() {
  let src = "(define one\n  ; one is the loneliest number\n  1)\n"
  let assert Ok(out) = formatter.format_source(src)
  case out == "(define one\n  ; one is the loneliest number\n  1)\n" {
    True -> Nil
    False -> panic as { "comment did not force a break:\n" <> out }
  }
}

/// The comment belongs to the form that encloses it, not the outermost one.
pub fn interior_comment_of_a_nested_form_test() {
  let src = "(define (shout)\n  (do Console print\n    ; louder\n    \"hi\"))\n"
  let assert Ok(out) = formatter.format_source(src)
  case
    out
    == "(define (shout)\n  (do Console\n    print\n    ; louder\n    \"hi\"))\n"
  {
    True -> Nil
    False -> panic as { "nested comment misplaced:\n" <> out }
  }
}

/// A comment after the last child, before the closer, is still inside.
pub fn comment_before_the_closer_stays_inside_test() {
  let src = "(define answer\n  42\n  ; why\n)\n"
  let assert Ok(out) = formatter.format_source(src)
  case out == "(define answer\n  42\n  ; why\n)\n" {
    True -> Nil
    False -> panic as { "pre-closer comment moved:\n" <> out }
  }
}

/// A comment after the closer on the closer's own line trails the form; it
/// must not be handed to whatever comes next.
pub fn comment_after_a_broken_closer_trails_the_form_test() {
  let src =
    "(define (long-name alpha beta gamma delta)\n  (chain ((a alpha) (b beta) (c gamma)) (add a b))) ; why\n(define two 2)\n"
  let assert Ok(out) = formatter.format_source(src)
  // The comment belongs to the form that closed, not to the form that follows:
  // it stays on the closer's line.
  case string.contains(out, "))) ; why\n(define two 2)\n") {
    True -> Nil
    False -> panic as { "closing-line comment misplaced:\n" <> out }
  }
}

/// Formatting is a fixed point, comments included.
pub fn interior_comments_are_idempotent_test() {
  let src =
    "(define answer\n  ; meaning\n  42\n  ; why\n)\n(define (shout)\n  (do Console print\n    ; louder\n    \"hi\"))\n"
  let assert Ok(once) = formatter.format_source(src)
  let assert Ok(twice) = formatter.format_source(once)
  case once == twice {
    True -> Nil
    False -> panic as { "not idempotent:\n" <> once <> "\n---\n" <> twice }
  }
}

pub fn semicolon_inside_a_string_is_untouched_test() {
  let src = "(define s \"a;b\")\n"
  let assert Ok(out) = formatter.format_source(src)
  case string.contains(out, "\"a;b\"") {
    True -> Nil
    False -> panic as { "string content mangled:\n" <> out }
  }
}

pub fn comments_are_idempotent_test() {
  let src = "; head\n(define answer 42) ; tail\n; foot\n"
  let assert Ok(once) = formatter.format_source(src)
  let assert Ok(twice) = formatter.format_source(once)
  case once == twice {
    True -> Nil
    False -> panic as { "not idempotent:\n" <> once <> "\n---\n" <> twice }
  }
}

pub fn comment_only_file_survives_test() {
  let src = "; nothing here\n; move along\n"
  let assert Ok(out) = formatter.format_source(src)
  case out == src {
    True -> Nil
    False -> panic as { "comment-only file mangled:\n" <> out }
  }
}

/// A comment on the same line as a form's *opening* is not a comment on the
/// form: if the form spans several lines the comment is inside it, describing
/// the child it follows. Only a comment after the form's closer, on the
/// closer's line, trails the form.
pub fn a_comment_on_the_opening_line_is_still_inside_test() {
  let src = "(define xs (quote (1 ; the one\n  2)))\n"
  let assert Ok(out) = formatter.format_source(src)
  case string.contains(out, "; the one\n") {
    True -> Nil
    False -> panic as { "comment inside a quoted form escaped it:\n" <> out }
  }
  case string.contains(out, "))) ; the one") {
    False -> Nil
    True -> panic as { "comment was appended after the form:\n" <> out }
  }
}

/// The same rule inside a nested child, not only at top level.
pub fn a_comment_inside_a_multiline_child_test() {
  let src = "(define (f x) (add x (chain ((a x)) ; why a\n (add a 1))))\n"
  let assert Ok(out) = formatter.format_source(src)
  case string.contains(out, "; why a") {
    True -> Nil
    False -> panic as { "comment lost:\n" <> out }
  }
  let assert Ok(twice) = formatter.format_source(out)
  case twice == out {
    True -> Nil
    False -> panic as { "not idempotent:\n" <> out <> "\n---\n" <> twice }
  }
}

/// A CRLF file formats, and its comments survive with the line endings
/// normalized.
pub fn a_crlf_file_formats_test() {
  let src = "(define x\r\n  ; why\r\n  1)\r\n"
  let assert Ok(out) = formatter.format_source(src)
  case out == "(define x\n  ; why\n  1)\n" {
    True -> Nil
    False -> panic as { "CRLF file mangled:\n" <> out }
  }
}
