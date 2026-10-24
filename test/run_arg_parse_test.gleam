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

/// Text is text, not a byte list. `~tp` only prints a binary as a string when
/// every byte is printable Latin-1, so `run` on a definition returning UTF-8
/// text printed <<104,195,169,108,108,111>> — the term, and nothing a human
/// could read. The shape stays the one the REPL uses.
pub fn unicode_text_renders_as_text_test() {
  parsed("\"héllo ✓\"") |> should.equal("<<\"héllo ✓\">>")
}

pub fn escaped_bytes_stay_escaped_inside_the_quotes_test() {
  parsed("\"a\\\"b\"") |> should.equal("<<\"a\\\"b\">>")
  parsed("\"a\\nb\"") |> should.equal("<<\"a\\nb\">>")
}

pub fn non_text_bytes_stay_bytes_test() {
  // A payload that is not valid UTF-8 is not text; showing it as one would lie.
  let assert Ok(term) = parse_term_arg("\"\\xff\"")
  render(term) |> should.equal("<<255>>")
}
