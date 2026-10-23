//// The store's read path: a ref is the identity, so a payload that does not
//// hash to its key must never reach the decoder.

import gleam/bit_array
import gleeunit/should
import gleamunison/ast
import gleamunison/codebase
import gleamunison/identity.{Ref, hash_bytes}

pub fn get_round_trips_an_inserted_definition_test() {
  let definition = ast.TermDef(term: ast.Int(42), typ: ast.Builtin(ast.IntType))
  let ref = Ref(codebase.hash_of_definition(definition))
  let cb = codebase.empty()
  let assert Ok(cb) =
    codebase.insert(cb, ast.Unit(root: ref, defs: [#(ref, definition)]))
  let assert Ok(stored) = codebase.get(cb, ref)
  stored |> should.equal(definition)
}

pub fn get_reports_not_found_for_an_absent_ref_test() {
  let ref = Ref(hash_bytes(<<"never-inserted">>))
  let assert Error(codebase.NotFound(got)) =
    codebase.get(codebase.empty(), ref)
  got |> should.equal(ref)
}

pub fn get_refuses_content_that_does_not_match_its_ref_test() {
  let ref = Ref(hash_bytes(<<"declared-ref">>))
  let cb = codebase.empty()
  let adapter = codebase.get_adapter(cb)
  let assert Ok(Nil) =
    adapter.insert(ref, bit_array.from_string("not the definition"))
  let assert Error(codebase.Corrupt(got, _)) = codebase.get(cb, ref)
  got |> should.equal(ref)
}
