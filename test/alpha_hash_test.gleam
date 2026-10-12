import gleamunison/ast
import gleamunison/codebase
import gleamunison/elab_types.{
  type SurfaceTerm, SInt, SLambda, SVar, SurfaceTermDef, SurfaceUnit,
}
import gleamunison/elaborate as elab
import gleamunison/identity.{Ref, hash_bytes, hash_to_debug_string}
import gleamunison/types.{empty_cache}

fn hash_single_def(name: String, body: SurfaceTerm) -> String {
  let cache = empty_cache()
  let surface =
    SurfaceUnit(root: Ref(hash_bytes(<<"root">>)), defs: [
      #(name, SurfaceTermDef(body)),
    ])
  let assert Ok(#(unit, _, _)) = elab.elaborate_unit(surface, cache)
  let assert ast.Unit(root: _, defs: [#(_ref, def)]) = unit
  hash_to_debug_string(codebase.hash_of_definition(def))
}

pub fn alpha_equivalent_lambdas_hash_identically_test() {
  let h1 = hash_single_def("f", SLambda("x", SVar("x")))
  let h2 = hash_single_def("g", SLambda("y", SVar("y")))
  let assert True = h1 == h2
}

pub fn nested_alpha_equivalence_test() {
  let h1 = hash_single_def("const1", SLambda("a", SLambda("b", SVar("a"))))
  let h2 = hash_single_def("const2", SLambda("x", SLambda("y", SVar("x"))))
  let assert True = h1 == h2
}

pub fn binder_shadowing_is_structural_test() {
  let h1 = hash_single_def("f", SLambda("x", SLambda("x", SVar("x"))))
  let h2 = hash_single_def("g", SLambda("a", SLambda("b", SVar("b"))))
  let assert True = h1 == h2
}

pub fn different_bodies_hash_differently_test() {
  let h1 = hash_single_def("f", SLambda("x", SVar("x")))
  let h2 = hash_single_def("f", SLambda("x", SInt(1)))
  let assert False = h1 == h2
}

pub fn binder_identity_is_index_not_name_test() {
  let cache = empty_cache()
  let surface =
    SurfaceUnit(root: Ref(hash_bytes(<<"root">>)), defs: [
      #("id", SurfaceTermDef(SLambda("whatever", SVar("whatever")))),
    ])
  let assert Ok(#(unit, _, _)) = elab.elaborate_unit(surface, cache)
  let assert ast.Unit(root: _, defs: [#(_ref, def)]) = unit
  let assert ast.TermDef(term: ast.Lambda(binder:, body:), typ: _) = def
  let assert ast.LocalVarRef(bv) = body
  let assert True = binder == bv
}
