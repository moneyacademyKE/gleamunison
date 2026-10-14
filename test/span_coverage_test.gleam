import gleamunison/elab_types.{SInt, SLambda, SLet, SLoc, SMatch, SUse, SVar}
import gleamunison/lexer.{ParseError}
import gleamunison/parser

// --- form-level SLoc wraps ---

pub fn let_form_carries_span_test() {
  let assert Ok(SLoc(SLet("x", SInt(1), _), span)) =
    parser.parse_string("(let x 1 x)")
  let assert elab_types.Span(1, 1) = span
}

pub fn lam_form_carries_span_test() {
  let assert Ok(SLoc(SLambda("x", _), span)) = parser.parse_string("(lam x x)")
  let assert elab_types.Span(1, 1) = span
}

pub fn if_form_carries_span_test() {
  let assert Ok(SLoc(SMatch(_, _), span)) = parser.parse_string("(if 1 2 3)")
  let assert elab_types.Span(1, 1) = span
}

pub fn match_form_carries_span_test() {
  let assert Ok(SLoc(SMatch(_, _), span)) =
    parser.parse_string("(match x (1 2))")
  let assert elab_types.Span(1, 1) = span
}

pub fn use_form_carries_span_test() {
  let assert Ok(SLoc(SUse("x", _, _), span)) =
    parser.parse_string("(use x (f 1) x)")
  let assert elab_types.Span(1, 1) = span
}

pub fn innermost_span_still_wins_inside_wrapped_forms_test() {
  // The let form is wrapped, but the body var keeps its own (inner) span.
  let assert Ok(SLoc(SLet(_, _, SLoc(SVar("x"), inner)), outer)) =
    parser.parse_string("(let x 1 x)")
  let assert elab_types.Span(1, 1) = outer
  let assert elab_types.Span(1, 10) = inner
}

// --- no more (0,0) parse errors ---

pub fn invalid_match_case_reports_position_test() {
  let assert Error(ParseError(_, l, c)) = parser.parse_string("(match x 42)")
  let assert True = l > 0 && c > 0
}

pub fn invalid_use_binder_reports_position_test() {
  let assert Error(ParseError(_, l, c)) =
    parser.parse_string("(use 42 (f 1) x)")
  let assert True = l > 0 && c > 0
}

pub fn invalid_fn_star_params_reports_position_test() {
  let assert Error(ParseError(_, l, c)) = parser.parse_string("(fn* 42 body)")
  let assert True = l > 0 && c > 0
}

pub fn invalid_let_star_pair_reports_position_test() {
  let assert Error(ParseError(_, l, c)) = parser.parse_string("(let* (x 1) x)")
  let assert True = l > 0 && c > 0
}

pub fn invalid_pattern_reports_position_test() {
  let assert Error(ParseError(_, l, c)) =
    parser.parse_string("(match x ((((1)) 2)))")
  let assert True = l > 0 && c > 0
}
