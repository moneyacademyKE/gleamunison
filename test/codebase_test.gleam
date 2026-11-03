import gleamunison/ast
import gleamunison/codebase.{
  Corrupt, DecodeFailed, DuplicateDef, HashMismatch, NotFound, StorageFailure,
  describe_insert_error, describe_read_error, empty, hash_of_definition, insert,
}
import gleamunison/identity.{Local, Ref, hash_bytes, hash_equal, ref_hex}
import gleamunison/storage
import gleeunit/should

pub fn typedef_distinct_hash_test() {
  let t1 =
    ast.TypeDef(ast.Structural(Local(0), [], [ast.Constructor(Local(0), [])]))
  let t2 =
    ast.TypeDef(ast.Structural(Local(1), [], [ast.Constructor(Local(1), [])]))
  let h1 = hash_of_definition(t1)
  let h2 = hash_of_definition(t2)
  let assert False = hash_equal(h1, h2)
}

pub fn ability_distinct_hash_test() {
  let a1 =
    ast.AbilityDecl(
      ast.AbilityDeclaration(Local(0), [
        ast.Operation(Local(0), [], ast.TypeRefBuiltin(ast.IntType)),
      ]),
    )
  let a2 =
    ast.AbilityDecl(
      ast.AbilityDeclaration(Local(0), [
        ast.Operation(Local(0), [], ast.TypeRefBuiltin(ast.FloatType)),
      ]),
    )
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

pub fn describe_insert_error_renders_sentences_test() {
  let expected = hash_bytes(<<"expected">>)
  let got = hash_bytes(<<"got">>)
  describe_insert_error(HashMismatch(expected, got))
  |> should.equal(
    "hash mismatch: expected "
    <> ref_hex(Ref(expected))
    <> ", got "
    <> ref_hex(Ref(got)),
  )
  let existing = Ref(hash_bytes(<<"existing">>))
  let incoming = Ref(hash_bytes(<<"incoming">>))
  describe_insert_error(DuplicateDef(existing, incoming))
  |> should.equal(
    "duplicate definition: "
    <> ref_hex(incoming)
    <> " already stored as "
    <> ref_hex(existing),
  )
  describe_insert_error(StorageFailure(storage.NotFound))
  |> should.equal("not found")
  describe_insert_error(StorageFailure(storage.IoError("disk offline")))
  |> should.equal("io error: disk offline")
}

pub fn describe_read_error_renders_sentences_test() {
  let ref = Ref(hash_bytes(<<"missing">>))
  describe_read_error(NotFound(ref))
  |> should.equal("not in the store")
  describe_read_error(codebase.StoreFailure(storage.NotFound))
  |> should.equal("not found")
  describe_read_error(codebase.StoreFailure(storage.IoError("disk offline")))
  |> should.equal("io error: disk offline")
  describe_read_error(Corrupt(ref, "checksum failed"))
  |> should.equal("content does not match its ref: checksum failed")
  describe_read_error(DecodeFailed(ref, "bad tag"))
  |> should.equal("payload is not a definition: bad tag")
}
