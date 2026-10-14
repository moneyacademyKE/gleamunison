import gleamunison/elab_ctx
import gleamunison/elab_term
import gleamunison/elab_types.{
  SInt, SLet, SLoc, SUse, SVar,
}
import gleamunison/parser

pub fn let_star_desugars_to_nested_slet_test() {
  let assert Ok(term) = parser.parse_string("(let* ((x 1) (y 2)) x)")
  // (let* ((x 1) (y 2)) x) ≡ (let x 1 (let y 2 x))
  let assert SLet("x", SInt(1), rest) = term
  let assert SLet("y", SInt(2), SLoc(SVar("x"), _)) = rest
}

pub fn let_star_single_binding_test() {
  let assert Ok(term) = parser.parse_string("(let* ((x 1)) x)")
  let assert SLet("x", SInt(1), SLoc(SVar("x"), _)) = term
}

pub fn let_star_empty_bindings_is_body_test() {
  let assert Ok(term) = parser.parse_string("(let* () 42)")
  let assert SInt(42) = term
}

pub fn chain_desugars_to_nested_suse_test() {
  let assert Ok(term) = parser.parse_string("(chain ((x (f 1)) (y (g 2))) y)")
  // (chain (x e1) (y e2) body) ≡ (use x e1 (use y e2 body))
  let assert SUse("x", _, rest) = term
  let assert SUse("y", _, SLoc(SVar("y"), _)) = rest
}

pub fn chain_single_binding_test() {
  let assert Ok(term) = parser.parse_string("(chain ((x (f 1))) x)")
  let assert SUse("x", _, SLoc(SVar("x"), _)) = term
}

pub fn let_star_elaborates_test() {
  let assert Ok(term) = parser.parse_string("(let* ((x 1) (y 2)) y)")
  let assert Ok(_) = elab_term.elaborate_term(term, elab_ctx.empty_elab_ctx())
}

pub fn chain_elaborates_test() {
  let assert Ok(term) = parser.parse_string("(chain ((x (lam a a))) x)")
  let assert Ok(_) = elab_term.elaborate_term(term, elab_ctx.empty_elab_ctx())
}

pub fn let_star_bad_pair_shape_errors_test() {
  let assert Error(_) = parser.parse_string("(let* (x 1) x)")
}

pub fn chain_bad_pair_shape_errors_test() {
  let assert Error(_) = parser.parse_string("(chain ((x)) x)")
}

pub fn let_star_requires_body_test() {
  let assert Error(_) = parser.parse_string("(let* ((x 1)))")
}
