import gleamunison/elab_ctx.{empty_elab_ctx}
import gleamunison/elab_term
import gleamunison/elab_types
import gleamunison/parser

pub fn unknown_variable_reports_span_test() {
  let assert Ok(term) = parser.parse_string("undefined_name")
  let result = elab_term.elaborate_term(term, empty_elab_ctx())
  let assert Error(elab_types.At(
    elab_types.NameNotFound("undefined_name"),
    span,
  )) = result
  let assert elab_types.Span(1, 1) = span
}

pub fn unknown_ability_reports_span_test() {
  let assert Ok(term) = parser.parse_string("(do NoSuchAbility op 1)")
  let result = elab_term.elaborate_term(term, empty_elab_ctx())
  let assert Error(elab_types.At(elab_types.MissingAbilityDecl(_), span)) =
    result
  let assert elab_types.Span(1, 1) = span
}

pub fn error_inside_lambda_reports_inner_span_test() {
  let assert Ok(term) = parser.parse_string("(lam x\n  missing_thing)")
  let result = elab_term.elaborate_term(term, empty_elab_ctx())
  let assert Error(elab_types.At(elab_types.NameNotFound("missing_thing"), span)) =
    result
  let assert elab_types.Span(2, _) = span
}

pub fn known_name_still_elaborates_test() {
  let assert Ok(term) = parser.parse_string("(lam x x)")
  let assert Ok(_) = elab_term.elaborate_term(term, empty_elab_ctx())
}
