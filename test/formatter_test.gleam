import gleamunison/formatter
import gleeunit/should

/// Short forms stay flat; redundant whitespace collapses.
pub fn short_define_stays_flat_test() {
  let messy = "(define   (add2   x y)\n(add x y))\n"
  let assert Ok(out) = formatter.format_source(messy)
  out |> should.equal("(define (add2 x y) (add x y))\n")
}

/// A form wider than 72 columns breaks after the head; children indent 2.
pub fn long_form_breaks_after_head_test() {
  let messy =
    "(define (long-function-name alpha beta gamma) (chain ((a alpha) (b beta) (c gamma)) (add a (add b c))))"
  let assert Ok(out) = formatter.format_source(messy)
  out
  |> should.equal(
    "(define (long-function-name alpha beta gamma)\n  (chain ((a alpha) (b beta) (c gamma)) (add a (add b c))))\n",
  )
}

/// Children that still overflow at their indent break recursively.
pub fn nested_break_indents_four_test() {
  let messy =
    "(define prog (chain ((aaaaaaaaaaaaaaaa state-get) (bbbbbbbbbbbbbbbb state-get) (cccccccccccccccc state-get)) (state-returns aaaaaaaaaaaaaaaa)))"
  let assert Ok(out) = formatter.format_source(messy)
  out
  |> should.equal(
    "(define prog\n  (chain\n    ((aaaaaaaaaaaaaaaa state-get)\n      (bbbbbbbbbbbbbbbb state-get)\n      (cccccccccccccccc state-get))\n    (state-returns aaaaaaaaaaaaaaaa)))\n",
  )
}

/// Idempotence: formatting a formatted file is a fixed point.
pub fn format_is_idempotent_test() {
  let messy =
    "(define   (add2   x y)\n(add x y))\n\n\n(define (long-function-name alpha beta gamma) (chain ((a alpha) (b beta) (c gamma)) (add a (add b c))))\n(define one 1)"
  let assert Ok(once) = formatter.format_source(messy)
  let assert Ok(twice) = formatter.format_source(once)
  twice |> should.equal(once)
}

/// Multiple top-level forms: one per line, no blank lines.
pub fn top_level_forms_one_per_line_test() {
  let messy = "(define one 1)\n\n\n\n(define two 2)\n\n"
  let assert Ok(out) = formatter.format_source(messy)
  out |> should.equal("(define one 1)\n(define two 2)\n")
}

/// Quote sugar normalizes to the explicit form (same program, one spelling).
pub fn quote_sugar_normalizes_test() {
  let assert Ok(out) = formatter.format_source("(define xs '(1 2))")
  out |> should.equal("(define xs (quote (1 2)))\n")
}

/// Comments are data: the formatter preserves them.
pub fn comments_preserved_test() {
  let assert Ok(out) = formatter.format_source("; hello\n(define one 1)")
  out |> should.equal("; hello\n(define one 1)\n")
}

/// Parse errors carry position, not a crash.
pub fn unbalanced_parens_error_test() {
  let assert Error(_) = formatter.format_source("(define one 1")
}

/// Atoms nobody should split: strings keep their quotes verbatim.
pub fn strings_pass_through_verbatim_test() {
  let assert Ok(out) =
    formatter.format_source("(define greeting \"hello, (world)  foo\")")
  out |> should.equal("(define greeting \"hello, (world)  foo\")\n")
}
