import gleam/int
import gleam/list
import gleam/string
import gleamunison/cli_datalog
import gleamunison/codebase_index
import gleamunison/elab_types
import gleamunison/formatter
import gleamunison/identity
import gleamunison/lsp
import gleamunison/mcp_session
import gleamunison/parser
import gleamunison/repl_eval
import gleamunison/source_budget
import gleamunison/types
import gleamunison/verify
import gleeunit/should
import simplifile

fn deep_source() -> String {
  string.repeat("(lam x ", 5000) <> "1" <> string.repeat(")", 5000)
}

pub fn deep_source_refuses_at_parser_formatter_lsp_and_datalog_test() {
  let source = deep_source()
  parser.parse_string(source) |> should.be_error
  formatter.format_source(source) |> should.be_error
  let assert [diagnostic] = lsp.diagnose(source)
  string.contains(diagnostic.message, "source limit") |> should.equal(True)
  cli_datalog.eval_source(source) |> should.be_error
}

pub fn byte_limit_applies_before_grapheme_token_allocation_test() {
  parser.parse_string("\"" <> string.repeat("a", 1_048_576) <> "\"")
  |> should.be_error
}

pub fn file_verification_and_mcp_load_refuse_before_compilation_test() {
  let path = "/tmp/gleamunison-source-budget-test.lisp"
  let assert Ok(_) = simplifile.write(deep_source(), to: path)
  verify.verify_file(path) |> should.be_error
  mcp_session.load_file(mcp_session.from_parts(types.empty_cache(), []), path)
  |> should.be_error
  let assert Ok(_) = simplifile.delete(path)
}

pub fn quoted_delimiters_and_comments_are_not_source_depth_test() {
  let text = string.repeat("( ) ; '", 1100)
  parser.parse_string("\"" <> text <> "\"")
  |> should.equal(Ok(elab_types.SText(<<text:utf8>>)))
  parser.parse_string(";" <> text <> "\n42")
  |> should.equal(Ok(elab_types.SInt(42)))
}

pub fn each_budget_is_inclusive_and_refuses_one_over_test() {
  let budget =
    source_budget.Budget(
      bytes: 4,
      tokens: 3,
      depth: 2,
      forms: 2,
      token_bytes: 4,
    )
  source_budget.check_with("café", budget)
  |> should.equal(Error("source limit: bytes"))
  source_budget.check_with("1234", budget) |> should.equal(Ok(Nil))
  source_budget.check_with("1 2", budget) |> should.equal(Ok(Nil))
  source_budget.check_with("1 2 3", source_budget.Budget(..budget, bytes: 20))
  |> should.equal(Error("source limit: forms"))
  source_budget.check_with("(1)", budget) |> should.equal(Ok(Nil))
  source_budget.check_with("(1 2)", source_budget.Budget(..budget, bytes: 20))
  |> should.equal(Error("source limit: tokens"))
  source_budget.check_with("'''1", source_budget.Budget(..budget, tokens: 10))
  |> should.equal(Error("source limit: depth"))
  source_budget.check_with(
    "'('(1))",
    source_budget.Budget(..budget, bytes: 20, tokens: 20),
  )
  |> should.equal(Error("source limit: depth"))
  source_budget.check_with("12345", source_budget.Budget(..budget, bytes: 20))
  |> should.equal(Error("source limit: token bytes"))
}

pub fn adjacent_forms_and_escaped_strings_do_not_bypass_limits_test() {
  let budget =
    source_budget.Budget(
      bytes: 100,
      tokens: 20,
      depth: 4,
      forms: 1,
      token_bytes: 100,
    )
  source_budget.check_with("1(2)", budget)
  |> should.equal(Error("source limit: forms"))
  source_budget.check_with("'('\"(\\\";\"')", budget) |> should.equal(Ok(Nil))
  source_budget.check_with("'('('1))", budget)
  |> should.equal(Error("source limit: depth"))
}

pub fn generated_index_does_not_spend_depth_per_datom_test() {
  let defs =
    list.index_fold(list.repeat(Nil, 400), [], fn(defs, _, n) {
      [
        #(int.to_string(n), elab_types.SurfaceTermDef(elab_types.SInt(n))),
        ..defs
      ]
    })
  source_budget.check(codebase_index.index_source(defs))
  |> should.equal(Ok(Nil))
}

/// Source written with CRLF line endings is the same program. `\r` is a line
/// break, not a symbol byte: without this, a file saved on Windows parsed as
/// `undefined variable "\r"` with no hint that the file was fine.
pub fn crlf_line_endings_parse_like_lf_test() {
  let lf = "(define (f) 1)\n(define (g) (f))\n"
  let crlf = "(define (f) 1)\r\n(define (g) (f))\r\n"
  parser.parse_string(crlf) |> should.equal(parser.parse_string(lf))
  source_budget.check(crlf) |> should.equal(Ok(Nil))
}

/// Control bytes are not source text. Before this, a NUL or an ESC became part
/// of a symbol: it reached identifiers, error messages, and terminal output,
/// which is an escape-sequence injection surface for anything that lists names.
pub fn control_characters_are_refused_not_tokenized_test() {
  source_budget.check("(define (f\u{1}x) 1)")
  |> should.equal(Error("source limit: control character U+0001"))
  source_budget.check("(define (f) 1) ; comment\u{1b}[31m")
  |> should.equal(Error("source limit: control character U+001B"))
  parser.parse_string("(define (f\u{1}x) 1)") |> should.be_error
  // Tab and newline are source whitespace, not control characters.
  source_budget.check("(define (f)\t1)\n") |> should.equal(Ok(Nil))
}

/// The datalog engine is ~124 definitions of infrastructure. Printing a
/// `(defined ...)` line for each one put the engine's setup on stdout before
/// the script's own answer, so `datalog script.lisp` could not be piped.
/// eval_source still reports every top-level value; the CLI path does not.
pub fn datalog_script_output_excludes_engine_definitions_test() {
  let path = "/tmp/gleamunison-datalog-output-test.lisp"
  let assert Ok(_) = simplifile.write("(+ 1 2)\n", to: path)
  let assert Ok(out) = cli_datalog.run(path)
  out |> should.equal("3")
}

/// The HTTP eval surface used a stateless evaluator with no baseline, so
/// `/eval?expr=(+ 1 2)` answered "undefined variable `+`". A define also only
/// recorded source text. One live session owns both.
pub fn session_define_then_eval_sees_the_name_test() {
  let state = mcp_session.boot()
  let assert Ok(#("foo", state)) = mcp_session.define_source(state, "foo", "42")
  let assert Ok(#(value, _)) = mcp_session.eval_source(state, "(+ foo 1)")
  value |> should.equal("43")
}

pub fn session_eval_has_the_baseline_environment_test() {
  let state = mcp_session.boot()
  let assert Ok(#(value, _)) = mcp_session.eval_source(state, "(+ 1 2)")
  value |> should.equal("3")
}

/// `find` promises a hash you can reference. For a builtin it printed
/// `#000000000000`: the synthetic handle the runtime uses internally for a
/// builtin's definition, which nothing can resolve. The name ref is what the
/// elaborator emits, so that is what a caller gets.
pub fn find_reports_a_reference_that_resolves_test() {
  let state = mcp_session.boot()
  let hits = mcp_session.search(state, "list-map")
  let assert [hit, ..] = hits
  let identity.Ref(name_hash) = repl_eval.ref_for_name("list-map")
  hit.ref_hex |> should.equal(identity.hash_to_debug_string(name_hash))
  // Not the synthetic genesis handle, whose hex starts with zeros.
  hit.ref_hex |> string.starts_with("0000000000") |> should.equal(False)
}
