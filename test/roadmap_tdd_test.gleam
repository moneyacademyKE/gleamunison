import gleam/list
import gleam/option.{Some, None}
import gleam/string
import gleamunison/identity.{Ref, hash_bytes}
import gleamunison/ast
import gleamunison/elab_types.{SInt, SVar, SList, SLet, SLambda}
import gleamunison/codebase.{hash_of_definition}
import gleamunison/parser
import gleamunison/lexer
import gleamunison/storage
import gleamunison/loader

pub fn sha256_hash_length_test() {
  let def = ast.TermDef(term: ast.Int(42), typ: ast.Builtin(ast.IntType))
  let hex_str = identity.hash_to_debug_string(hash_of_definition(def))
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

pub fn partitioned_dets_storage_test() {
  let path = "/tmp/test_partitioned_dets"
  let _ = storage.partitioned_dets_delete(path)
  let assert Ok(adapter) = storage.partitioned_dets(path)
  let ref1 = Ref(hash_bytes(<<"ref_a">>))
  let ref2 = Ref(hash_bytes(<<"ref_b">>))
  let data1 = <<"data a">>
  let data2 = <<"data b">>

  let assert Ok(None) = adapter.lookup(ref1)
  let assert Ok(None) = adapter.lookup(ref2)
  let assert Ok(Nil) = adapter.insert(ref1, data1)
  let assert Ok(Nil) = adapter.insert(ref2, data2)

  let assert Ok(Some(r1)) = adapter.lookup(ref1)
  let assert Ok(Some(r2)) = adapter.lookup(ref2)
  let assert True = r1 == data1 && r2 == data2

  let assert Ok(refs) = adapter.list_refs()
  let assert True = list.contains(refs, ref1) && list.contains(refs, ref2)

  let assert Ok(Nil) = adapter.close()
  let assert Ok(Nil) = storage.partitioned_dets_delete(path)
}

pub fn lru_purging_test() {
  let ld = loader.new_loader_with_limit(2)
  let ref1 = Ref(hash_bytes(<<"ref1">>))
  let ref2 = Ref(hash_bytes(<<"ref2">>))
  let ref3 = Ref(hash_bytes(<<"ref3">>))
  let def1 = ast.TermDef(term: ast.Int(1), typ: ast.Builtin(ast.IntType))
  let def2 = ast.TermDef(term: ast.Int(2), typ: ast.Builtin(ast.IntType))
  let def3 = ast.TermDef(term: ast.Int(3), typ: ast.Builtin(ast.IntType))

  let assert Ok(ld) = loader.ensure_loaded(ld, ref1, def1)
  let assert Ok(ld) = loader.ensure_loaded(ld, ref2, def2)
  let assert True = loader.is_loaded(ld, ref1) && loader.is_loaded(ld, ref2)

  let assert Ok(ld) = loader.ensure_loaded(ld, ref3, def3)
  let assert False = loader.is_loaded(ld, ref1)
  let assert True = loader.is_loaded(ld, ref2) && loader.is_loaded(ld, ref3)
}

@external(erlang, "gleamunison_ffi", "corrupt_handler_stack")
fn corrupt_handler_stack(val: String) -> Nil

@external(erlang, "gleamunison_ffi", "assert_throws_corrupted_stack")
fn assert_throws_corrupted_stack(fun: fn() -> Nil) -> Nil

@external(erlang, "gleamunison_effets", "do_op")
fn ffi_do_op(ability: String, op: Int, args: List(String), cont: fn(String) -> Nil) -> Nil

pub fn stack_corruption_protection_test() {
  corrupt_handler_stack("bad stack value")
  assert_throws_corrupted_stack(fn() {
    ffi_do_op("m_dummy", 0, [], fn(_) { Nil })
  })
}

pub fn parser_s_expression_test() {
  let assert Ok(SInt(42)) = parser.parse_string("42")
  let assert Ok(SVar("x")) = parser.parse_string("x")
  let assert Ok(SList([SInt(1), SInt(2)])) = parser.parse_string("(list 1 2)")
  let assert Ok(elab_types.SApply(SVar("add"), SInt(1))) = parser.parse_string("(add 1)")
  let assert Ok(SLet("x", SInt(42), SVar("x"))) = parser.parse_string("(let x 42 x)")
  let assert Ok(SLambda("x", SVar("x"))) = parser.parse_string("(lam x x)")
}

pub fn parser_coordinate_error_test() {
  let assert Error(lexer.ParseError(_msg, line, col)) =
    parser.parse_string("\n )")
  let assert 2 = line
  let assert 2 = col
}

@external(erlang, "gleamunison_storage", "test_make_ref")
fn test_make_ref(bytes: BitArray) -> identity.DefinitionRef

@external(erlang, "gleamunison_storage", "get_open_dets_count")
fn get_open_dets_count(prefix: String) -> Int

pub fn dets_fd_pool_test() {
  let path = "/tmp/test_fd_pool"
  let _ = storage.partitioned_dets_delete(path)
  let assert Ok(adapter) = storage.partitioned_dets(path)

  let refs = list.map(range(0, 15), fn(i) {
    test_make_ref(<<i:4, 0:252>>)
  })

  list.each(refs, fn(r) {
    let assert Ok(Nil) = adapter.insert(r, <<"data">>)
    Nil
  })

  let assert True = get_open_dets_count(path) <= 4

  let assert Ok(Some(<<"data">>)) = adapter.lookup(test_make_ref(<<0:4, 0:252>>))
  let assert Ok(Some(<<"data">>)) = adapter.lookup(test_make_ref(<<15:4, 0:252>>))

  let assert Ok(Nil) = adapter.close()
  let assert Ok(Nil) = storage.partitioned_dets_delete(path)
}

fn range(start: Int, end: Int) -> List(Int) {
  case start > end {
    True -> []
    False -> [start, ..range(start + 1, end)]
  }
}

@external(erlang, "gleamunison_ffi", "test_soft_purge_scenario")
fn test_soft_purge_scenario() -> Result(#(Bool, Bool), String)

pub fn soft_purge_test() {
  let assert Ok(#(False, True)) = test_soft_purge_scenario()
}

import gleamunison/repl_eval
import gleamunison/types.{empty_cache}
import gleamunison/repl_io

pub fn spelling_suggestions_test() {
  let prev_defs = [
    #("secret", elab_types.SurfaceTermDef(SInt(42))),
    #("guess", elab_types.SurfaceTermDef(SInt(0))),
  ]
  let assert Error(err) = repl_eval.do_eval(SVar("secre"), "test_expr", empty_cache(), prev_defs)
  let assert True = string.contains(err, "Did you mean: secret?")

  let assert Error(err2) = repl_eval.do_eval(SVar("nonexistent"), "test_expr", empty_cache(), prev_defs)
  let assert False = string.contains(err2, "Did you mean:")
}

pub fn repl_bracket_counting_test() {
  let assert 0 = repl_io.count_brackets("(let x 1 x)", False, 0)
  let assert 1 = repl_io.count_brackets("(let x 1", False, 0)
  let assert 0 = repl_io.count_brackets(" \"(let x 1\" ", False, 0)
  let assert 0 = repl_io.count_brackets(" \"hello \\\" (world \" ", False, 0)
}
