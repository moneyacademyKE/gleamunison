//// Whether a definition is effectful — the fact the evidence gate turns on.
////
//// A pure definition must be tested; an effectful one may instead carry a human
//// `io` attestation, because a suite cannot drive real IO. That decision needs
//// one answer to "is this effectful?", and it belongs to the term, not to the
//// command asking: `publish` and `run` must agree, or a definition gets admitted
//// by one gate and refused by the other.
////
//// The term is the honest source. A top-level value type carries no requirement
//// row, but an ability call is right there as a `Do` node.

import gleam/list
import gleam/option
import gleamunison/ast
import gleamunison/bootstrap_terms

pub fn definition_is_effectful(definition: ast.Definition) -> Bool {
  case definition {
    ast.TermDef(term:, ..) -> term_is_effectful(term)
    _ -> False
  }
}

pub fn term_is_effectful(term: ast.Term) -> Bool {
  case term {
    ast.Do(..) -> True
    ast.RefTo(ref) -> bootstrap_terms.is_host_ref(ref)
    ast.LocalVarRef(_) | ast.Int(_) | ast.Float(_) | ast.Text(_) | ast.Hole ->
      False
    ast.List(items) -> list.any(items, term_is_effectful)
    ast.Apply(f, a) -> term_is_effectful(f) || term_is_effectful(a)
    ast.Lambda(_, body) -> term_is_effectful(body)
    ast.Let(_, value, body) ->
      term_is_effectful(value) || term_is_effectful(body)
    ast.Match(scrutinee, cases) ->
      term_is_effectful(scrutinee) || list.any(cases, case_is_effectful)
    ast.Handle(comp, handler, _) ->
      term_is_effectful(comp) || term_is_effectful(handler)
    ast.Construct(_, args) -> list.any(args, term_is_effectful)
    ast.Use(_, call, body) -> term_is_effectful(call) || term_is_effectful(body)
    ast.Located(inner, _) -> term_is_effectful(inner)
  }
}

fn case_is_effectful(c: ast.Case) -> Bool {
  let guard_has = case c.guard {
    option.Some(ast.GuardTerm(t)) -> term_is_effectful(t)
    option.None -> False
  }
  guard_has || term_is_effectful(c.body)
}
