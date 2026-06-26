import gleamunison/identity.{Local, Ref, hash_bytes, hash_equal}
import gleamunison/ast
import gleamunison/codebase.{hash_of_definition, insert, empty, HashMismatch}

pub fn typedef_distinct_hash_test() {
  let t1 = ast.TypeDef(ast.Structural(Local(0), [], [ast.Constructor(Local(0), [])]))
  let t2 = ast.TypeDef(ast.Structural(Local(1), [], [ast.Constructor(Local(1), [])]))
  let h1 = hash_of_definition(t1)
  let h2 = hash_of_definition(t2)
  let assert False = hash_equal(h1, h2)
}

pub fn ability_distinct_hash_test() {
  let a1 = ast.AbilityDecl(ast.AbilityDeclaration(Local(0), [ast.Operation(Local(0), [], ast.TypeRefBuiltin(ast.IntType))]))
  let a2 = ast.AbilityDecl(ast.AbilityDeclaration(Local(0), [ast.Operation(Local(0), [], ast.TypeRefBuiltin(ast.FloatType))]))
  let h1 = hash_of_definition(a1)
  let h2 = hash_of_definition(a2)
  let assert False = hash_equal(h1, h2)
}

pub fn hash_mismatch_labels_test() {
  let cb = empty()
  let term = ast.Int(42)
  let typ = ast.Builtin(ast.IntType)
  let def = ast.TermDef(term:, typ:)
  let computed = hash_of_definition(def)
  let wrong_ref = Ref(hash_bytes(<<"wrong_hash">>))
  
  let unit = ast.Unit(wrong_ref, [#(wrong_ref, def)])
  let assert Error(HashMismatch(expected, got)) = insert(cb, unit)
  
  let Ref(wrong_hash) = wrong_ref
  let assert True = hash_equal(expected, computed)
  let assert True = hash_equal(got, wrong_hash)
}
