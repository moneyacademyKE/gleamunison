//// CLI arguments become Erlang terms. The parser is the only place that
//// decides, and it is deliberately narrow: an integer is an integer, text is
//// text, and a caller that wants raw text asks for it explicitly.

import gleeunit/should

@external(erlang, "gleamunison_ffi", "parse_term_arg")
fn parse_term_arg(arg: String) -> Result(Dynamic, Nil)

pub type Dynamic

@external(erlang, "gleamunison_ffi", "render_term")
fn render(term: Dynamic) -> String

fn parsed(arg: String) -> String {
  case parse_term_arg(arg) {
    Ok(term) -> render(term)
    Error(_) -> "REFUSED"
  }
}

pub fn an_integer_argument_parses_test() {
  parsed("42") |> should.equal("42")
}

pub fn a_negative_integer_parses_test() {
  parsed("-7") |> should.equal("-7")
}

pub fn a_float_parses_test() {
  parsed("1.5") |> should.equal("1.5")
}

pub fn atoms_parse_test() {
  parsed("true") |> should.equal("true")
  parsed("nil") |> should.equal("nil")
}

pub fn quoted_text_parses_test() {
  parsed("\"hi\"") |> should.equal("<<\"hi\">>")
}

pub fn a_bare_word_is_not_a_term_test() {
  // Deliberate: `hello` is text, and the CLI falls back to raw text for it.
  // The parser refuses so the fallback is explicit rather than accidental.
  parsed("hello") |> should.equal("REFUSED")
}

pub fn garbage_is_refused_test() {
  parsed("3x") |> should.equal("REFUSED")
  parsed("(1,") |> should.equal("REFUSED")
}
