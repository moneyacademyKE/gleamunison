import gleam/option
import gleamunison/ast
import gleamunison/elab_types.{
  SCase, SInt, SMatch, SPVar, SVar, SurfaceTermDef, SurfaceUnit,
}
import gleamunison/elaborate as elab
import gleamunison/identity.{Local, Ref, hash_bytes}
import gleamunison/types.{empty_cache}

pub fn elaborate_first_def_test() {
  let cache = empty_cache()
  let surface =
    SurfaceUnit(root: Ref(hash_bytes(<<"root">>)), defs: [
      #("my_first_def", SurfaceTermDef(SInt(42))),
    ])
  let assert Ok(#(unit, _, _)) = elab.elaborate_unit(surface, cache)
  let assert ast.Unit(root: _, defs: [#(_ref, def)]) = unit
  let assert ast.TermDef(term:, typ:) = def
  let assert ast.Int(42) = term
  let assert ast.Builtin(ast.IntType) = typ
}

pub fn elaborate_case_index_test() {
  let cache = empty_cache()
  let m =
    SMatch(SInt(42), [
      SCase(pattern: SPVar("x"), guard: option.None, body: SVar("x")),
      SCase(pattern: SPVar("y"), guard: option.None, body: SVar("y")),
    ])
  let surface =
    SurfaceUnit(root: Ref(hash_bytes(<<"root">>)), defs: [
      #("test_match", SurfaceTermDef(m)),
    ])
  let assert Ok(#(unit, _, _)) = elab.elaborate_unit(surface, cache)
  let assert ast.Unit(
    root: _,
    defs: [#(_ref, ast.TermDef(term: ast.Match(_, [c1, c2]), typ: _))],
  ) = unit
  let assert ast.Case(
    pattern: ast.PatVar(Local(i1)),
    guard: option.None,
    body: ast.LocalVarRef(Local(v1)),
  ) = c1
  let assert ast.Case(
    pattern: ast.PatVar(Local(i2)),
    guard: option.None,
    body: ast.LocalVarRef(Local(v2)),
  ) = c2
  let assert True = i1 == v1
  let assert True = i2 == v2
  let assert True = i1 == i2
}

pub fn typecheck_mismatch_test() {
  let cache = empty_cache()
  let ref = Ref(hash_bytes(<<"ref">>))
  let bad_unit =
    ast.Unit(root: ref, defs: [
      #(ref, ast.TermDef(term: ast.Int(42), typ: ast.Builtin(ast.FloatType))),
    ])
  let assert Error(_) = elab.typecheck_unit(bad_unit, cache)
}

pub fn typedef_constructor_distinct_local_test() {
  let cache = empty_cache()
  let surface =
    SurfaceUnit(root: Ref(hash_bytes(<<"root">>)), defs: [
      #(
        "MyType",
        elab_types.SurfaceTypeDef(elab_types.TBuiltin(elab_types.TInt)),
      ),
    ])
  let assert Ok(#(unit, _, _)) = elab.elaborate_unit(surface, cache)
  let assert ast.Unit(
    root: _,
    defs: [
      #(
        _ref,
        ast.TypeDef(ast.Structural(name, _, [ast.Constructor(c_name, _)])),
      ),
    ],
  ) = unit
  let assert False = name == c_name
}
