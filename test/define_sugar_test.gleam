import gleamunison/ast
import gleamunison/codebase
import gleamunison/elab_types.{
  type SurfaceTerm, SVar, SurfaceTermDef, SurfaceUnit,
}
import gleamunison/elaborate as elab
import gleamunison/identity.{Ref, hash_bytes, hash_to_debug_string}
import gleamunison/parser
import gleamunison/types.{empty_cache}
import gleeunit/should

/// Hash the elaborated value of a `(define name <value>)` parse. Content
/// hashing skips spans and binder names, so two spellings hash equal iff
/// they are the same program.
fn hash_define_value(source: String) -> String {
  let assert Ok(term) = parser.parse_string(source)
  let assert elab_types.SList([SVar("define"), SVar(_name), value]) = term
  hash_body(value)
}

fn hash_body(body: SurfaceTerm) -> String {
  let cache = empty_cache()
  let surface =
    SurfaceUnit(root: Ref(hash_bytes(<<"root">>)), defs: [
      #("f", SurfaceTermDef(body)),
    ])
  let assert Ok(#(unit, _, _)) = elab.elaborate_unit(surface, cache)
  let assert ast.Unit(root: _, defs: [#(_ref, def)]) = unit
  hash_to_debug_string(codebase.hash_of_definition(def))
}

/// `(define (f x y) body)` is the standard lisp function shorthand. It must
/// be the SAME PROGRAM as `(define f (lam x (lam y body)))` — proven by
/// identical content hashes.
pub fn define_function_sugar_is_curried_lams_test() {
  let sugared = hash_define_value("(define (add2 x y) x)")
  let plain = hash_define_value("(define add2 (lam x (lam y x)))")
  sugared |> should.equal(plain)
}

/// `(lam (x y) body)` == `(lam x (lam y body))`.
pub fn lam_list_params_are_curried_lams_test() {
  let sugared = hash_define_value("(define f (lam (x y) y))")
  let plain = hash_define_value("(define f (lam x (lam y y)))")
  sugared |> should.equal(plain)
}

/// The desugared define must still match the loader's bare-define shape:
/// SList([SVar("define"), SVar(name), _]).
pub fn define_sugar_keeps_loader_visible_shape_test() {
  let assert Ok(sugared) = parser.parse_string("(define (f x) x)")
  case sugared {
    elab_types.SList([SVar("define"), SVar("f"), _]) -> Nil
    _ -> panic as "sugar broke the bare-define shape loaders match on"
  }
}

/// `(define (f) body)` — zero params — is a plain value define.
pub fn define_zero_param_sugar_is_plain_define_test() {
  let sugared = hash_define_value("(define (answer) 42)")
  let plain = hash_define_value("(define answer 42)")
  sugared |> should.equal(plain)
}

/// Single-param list form matches the single-atom form too.
pub fn define_single_param_sugar_test() {
  let sugared = hash_define_value("(define (id x) x)")
  let plain = hash_define_value("(define id (lam x x))")
  sugared |> should.equal(plain)
}

/// Sugar composes with chain: the State program written with function-define
/// sugar is the same program as the curried spelling.
pub fn sugared_state_get_matches_curried_test() {
  let sugared = hash_define_value("(define (state-get k) (lam (s) ((k s) s)))")
  let plain = hash_define_value("(define state-get (lam k (lam s ((k s) s))))")
  sugared |> should.equal(plain)
}
