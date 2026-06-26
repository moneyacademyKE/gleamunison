import gleam/option.{Some, None}
import gleam/string
import gleamunison/identity.{Ref, hash_bytes}
import gleamunison/ast
import gleamunison/elab_types.{SInt, SVar, SList, SLet, SLambda}
import gleamunison/codebase.{hash_of_definition}
import gleamunison/parser
import gleamunison/storage

pub fn sha256_hash_length_test() {
  let def = ast.TermDef(term: ast.Int(42), typ: ast.Builtin(ast.IntType))
  let computed = hash_of_definition(def)
  let hex_str = identity.hash_to_debug_string(computed)
  let assert 64 = string.length(hex_str)
}

pub fn dets_storage_adapter_test() {
  let path = "/tmp/test_dets_db.dets"
  let _ = storage.dets_delete_file(path)
  let assert Ok(adapter) = storage.dets(path)
  let ref = Ref(hash_bytes(<<"test_dets_ref">>))
  let data = <<"hello dets">>
  let assert Ok(None) = adapter.lookup(ref)
  let assert Ok(Nil) = adapter.insert(ref, data)
  let assert Ok(Some(retrieved)) = adapter.lookup(ref)
  let assert True = retrieved == data
  let assert Ok(Nil) = adapter.close()
  let assert Ok(Nil) = storage.dets_delete_file(path)
}

pub fn parser_s_expression_test() {
  let assert Ok(SInt(42)) = parser.parse_string("42")
  let assert Ok(SVar("x")) = parser.parse_string("x")
  let assert Ok(SList([SInt(1), SInt(2)])) = parser.parse_string("(1 2)")
  let assert Ok(SLet("x", SInt(42), SVar("x"))) = parser.parse_string("(let x 42 x)")
  let assert Ok(SLambda("x", SVar("x"))) = parser.parse_string("(lam x x)")
}
