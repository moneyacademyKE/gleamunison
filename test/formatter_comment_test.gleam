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

pub fn interior_comment_hoists_before_the_form_test() {
  let src = "(define answer\n  ; the meaning of life\n  42)\n"
  let assert Ok(out) = formatter.format_source(src)
  case out == "; the meaning of life\n(define answer 42)\n" {
    True -> Nil
    False -> panic as { "interior comment not hoisted:\n" <> out }
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
