import gleam/list
import gleam/string
import gleamunison/elab_types.{SInt, SVar, SurfaceTermDef}
import gleamunison/lisp_literal
import gleamunison/mcp_session
import gleamunison/parser
import gleamunison/types
import gleeunit/should

pub fn hostile_query_arguments_are_literals_not_programs_test() {
  let state = mcp_session.from_parts(types.empty_cache(), [])
  list.each(["\"", "\\", "x\n\"))) (define injected 1) ;", "café🦀"], fn(value) {
    mcp_session.callers_of(state, value) |> should.equal(Ok([]))
    mcp_session.deps_of(state, value) |> should.equal(Ok([]))
    mcp_session.defs_by_kind(state, value) |> should.equal(Ok([]))
  })
}

pub fn graph_index_round_trips_hostile_names_and_unicode_test() {
  let target = "café🦀\"\\\n"
  let caller = "caller\"\\\n🦀"
  let state =
    mcp_session.from_parts(types.empty_cache(), [
      #(target, SurfaceTermDef(SInt(1))),
      #(caller, SurfaceTermDef(SVar(target))),
    ])
  mcp_session.callers_of(state, target) |> should.equal(Ok([caller]))
  mcp_session.deps_of(state, caller) |> should.equal(Ok([target]))
  let assert Ok(names) = mcp_session.defs_by_kind(state, "term")
  list.sort(names, string.compare)
  |> should.equal(list.sort([target, caller], string.compare))
}

pub fn literal_encoder_matches_lexer_escapes_exactly_test() {
  list.each(["", "\\n", "\"", "a\r\n\tb", "café🦀", ";)))\"\\"], fn(value) {
    parser.parse_string(lisp_literal.text(value))
    |> should.equal(Ok(elab_types.SText(<<value:utf8>>)))
  })
}

@external(erlang, "gleamunison_index_result", "strings")
fn result_strings(output: String) -> Result(List(String), String)

pub fn index_result_decoder_rejects_code_and_wrong_shapes_test() {
  list.each(
    [
      "[1]",
      "[foo]",
      "erlang:halt()",
      "[<<255>>]",
      "[<<\"x\">>] trailing",
      "[<<\"x\">>",
    ],
    fn(output) { result_strings(output) |> should.be_error },
  )
}
