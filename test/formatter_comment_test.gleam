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
  // too long to stay flat: breaks, comment still trails the first line
  let src =
    "(define some-rather-long-function-name-here (lam some-argument-name (add some-argument-name 1000))) ; doc\n"
  let assert Ok(out) = formatter.format_source(src)
  let first_line = case string.split(out, "\n") {
    [l, ..] -> l
    [] -> ""
  }
  case string.ends_with(first_line, "; doc") {
    True -> Nil
    False -> panic as { "trailing comment not on first line:\n" <> out }
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
  let first_line = case string.split(out, "\n") {
    [l, ..] -> l
    [] -> ""
  }
  case
    string.ends_with(first_line, "; why"),
    string.contains(out, "; why\n(define two 2)")
  {
    True, False -> Nil
    _, _ -> panic as { "closing-line comment escaped the form:\n" <> out }
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
