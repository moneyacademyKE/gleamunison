import gleam/dict
import gleamunison/ast
import gleamunison/elab_ctx
import gleamunison/elab_def
import gleamunison/types

import gleamunison/elab_term
import gleamunison/elab_types
import gleamunison/parser
import gleamunison/repl_eval

pub fn unknown_variable_reports_span_test() {
  let assert Ok(term) = parser.parse_string("undefined_name")
  let result = elab_term.elaborate_term(term, elab_ctx.empty_elab_ctx())
  let assert Error(elab_types.At(
    elab_types.NameNotFound("undefined_name"),
    span,
  )) = result
  let assert elab_types.Span(1, 1) = span
}

pub fn unknown_ability_reports_span_test() {
  let assert Ok(term) = parser.parse_string("(do NoSuchAbility op 1)")
  let result = elab_term.elaborate_term(term, elab_ctx.empty_elab_ctx())
  let assert Error(elab_types.At(elab_types.MissingAbilityDecl(_), span)) =
    result
  let assert elab_types.Span(1, 1) = span
}

pub fn error_inside_lambda_reports_inner_span_test() {
  let assert Ok(term) = parser.parse_string("(lam x\n  missing_thing)")
  let result = elab_term.elaborate_term(term, elab_ctx.empty_elab_ctx())
  let assert Error(elab_types.At(elab_types.NameNotFound("missing_thing"), span)) =
    result
  let assert elab_types.Span(2, _) = span
}

pub fn known_name_still_elaborates_test() {
  let assert Ok(term) = parser.parse_string("(lam x x)")
  let assert Ok(_) = elab_term.elaborate_term(term, elab_ctx.empty_elab_ctx())
}

pub fn nested_loc_error_keeps_innermost_span_test() {
  // (do Console print (helper-fn 1)): the unbound var sits inside a `do`
  // form. The error must cite the var (innermost), not stack spans.
  let ctx =
    elab_ctx.ElabCtx(
      names: dict.new(),
      bindings: dict.new(),
      next_local: 0,
      abilities: dict.from_list([
        #("Console", repl_eval.ref_for_name("Console")),
      ]),
      ops: dict.from_list([#(#("Console", "print"), 0)]),
    )
  let assert Ok(term) = parser.parse_string("(do Console print (helper-fn 1))")
  let result = elab_term.elaborate_term(term, ctx)
  let assert Error(elab_types.At(elab_types.NameNotFound("helper-fn"), span)) =
    result
  let assert elab_types.Span(1, 20) = span
}

pub fn application_error_cites_call_site_test() {
  // An unbound function in the head of an application cites the head,
  // and the application wrapper does not overwrite it with the call span.
  let assert Ok(term) = parser.parse_string("(missing-fn 42)")
  let result = elab_term.elaborate_term(term, elab_ctx.empty_elab_ctx())
  let assert Error(elab_types.At(elab_types.NameNotFound("missing-fn"), span)) =
    result
  let assert elab_types.Span(1, 2) = span
}

pub fn type_error_in_application_reports_arg_span_test() {
  // (add 1 greeting): add expects Int, greeting is Text. The failing node
  // is the argument `greeting` at col 8 — the error must cite it.
  let add_ref = repl_eval.ref_for_name("add")
  let greeting_ref = repl_eval.ref_for_name("greeting")
  let ctx =
    elab_ctx.ElabCtx(
      names: dict.from_list([
        #("add", add_ref),
        #("greeting", greeting_ref),
      ]),
      bindings: dict.new(),
      next_local: 0,
      abilities: dict.new(),
      ops: dict.new(),
    )
  let int = ast.Builtin(ast.IntType)
  let cache =
    types.TypeCache(
      entries: dict.from_list([
        #(add_ref, types.CTTerm(ast.Fn([int, int], int, ast.Required([])))),
        #(greeting_ref, types.CTTerm(ast.Builtin(ast.TextType))),
      ]),
    )
  let assert Ok(term) = parser.parse_string("(add 1 greeting)")
  let result =
    elab_def.elab_term_def(term, ctx, repl_eval.ref_for_name("bad"), cache)
  let assert Error(elab_types.At(elab_types.InferFailed(_msg), span)) = result
  let assert elab_types.Span(1, 8) = span
}
