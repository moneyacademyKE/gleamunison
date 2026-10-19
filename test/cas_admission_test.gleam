import gleam/bit_array
import gleam/option.{None, Some}
import gleam/string
import gleamunison/ast
import gleamunison/codebase
import gleamunison/identity.{Local, Ref, hash_bytes}
import gleamunison/storage
import gleamunison/sync
import gleamunison/sync_types.{PeerId}
import gleeunit/should

@external(erlang, "gleamunison_cas_test", "encode_definition")
fn encode_definition(def: ast.Definition) -> BitArray

@external(erlang, "gleamunison_cas_test", "scratch_path")
fn scratch_path() -> String

@external(erlang, "gleamunison_cas_test", "receive_defs")
fn receive_defs(defs: List(#(String, BitArray))) -> Result(Nil, String)

fn int_definition(value: Int) -> ast.Definition {
  ast.TermDef(ast.Int(value), ast.Builtin(ast.IntType))
}

pub fn forged_first_chunk_is_rejected_test() {
  let cb = codebase.empty()
  let ref = Ref(hash_bytes(<<"honest">>))
  sync.accept_chunk(PeerId("forger"), cb, ref, <<"forged">>)
  |> should.be_error
  codebase.get_adapter(cb).lookup(ref) |> should.equal(Ok(None))
}

pub fn codebase_reports_failed_storage_write_test() {
  let adapter = storage.inmemory()
  let broken =
    storage.StorageAdapter(..adapter, insert: fn(_, _) {
      Error(storage.IoError("injected storage failure"))
    })
  let def = int_definition(91)
  let ref = Ref(codebase.hash_of_definition(def))
  codebase.insert(codebase.with_adapter(broken), ast.Unit(ref, [#(ref, def)]))
  |> should.be_error
  adapter.lookup(ref) |> should.equal(Ok(None))
}

pub fn sync_reports_lookup_error_without_writing_test() {
  let adapter = storage.inmemory()
  let broken =
    storage.StorageAdapter(..adapter, lookup: fn(_) {
      Error(storage.IoError("injected read failure"))
    })
  let bytes = <<"valid content">>
  let ref = Ref(hash_bytes(bytes))
  sync.accept_chunk(PeerId("reader"), codebase.with_adapter(broken), ref, bytes)
  |> should.be_error
  adapter.lookup(ref) |> should.equal(Ok(None))
}

pub fn sync_reports_failed_write_test() {
  let adapter = storage.inmemory()
  let broken =
    storage.StorageAdapter(..adapter, insert: fn(_, _) {
      Error(storage.IoError("injected write failure"))
    })
  let bytes = <<"valid content">>
  sync.accept_chunk(
    PeerId("writer"),
    codebase.with_adapter(broken),
    Ref(hash_bytes(bytes)),
    bytes,
  )
  |> should.be_error
}

pub fn definition_storage_uses_rehashable_encoding_test() {
  let cb = codebase.empty()
  let def = int_definition(92)
  let ref = Ref(codebase.hash_of_definition(def))
  let assert Ok(cb) = codebase.insert(cb, ast.Unit(ref, [#(ref, def)]))
  codebase.get_adapter(cb).lookup(ref)
  |> should.equal(Ok(Some(encode_definition(def))))
}

pub fn structural_definition_transfers_test() {
  let def = int_definition(93)
  let ref = Ref(codebase.hash_of_definition(def))
  let bytes = encode_definition(def)
  let assert Ok(cb) =
    sync.accept_chunk(PeerId("honest"), codebase.empty(), ref, bytes)
  codebase.get_adapter(cb).lookup(ref) |> should.equal(Ok(Some(bytes)))
}

pub fn forged_definition_payload_is_rejected_test() {
  let ref = Ref(codebase.hash_of_definition(int_definition(94)))
  sync.accept_chunk(
    PeerId("forger"),
    codebase.empty(),
    ref,
    encode_definition(int_definition(95)),
  )
  |> should.be_error
}

pub fn legacy_inspect_definition_fails_closed_test() {
  let def = int_definition(96)
  sync.accept_chunk(
    PeerId("legacy"),
    codebase.empty(),
    Ref(codebase.hash_of_definition(def)),
    bit_array.from_string(string.inspect(def)),
  )
  |> should.be_error
}

pub fn pushed_batch_validates_before_first_insert_test() {
  let adapter = storage.inmemory()
  let bytes = <<"valid pushed blob">>
  let ref = Ref(hash_bytes(bytes))
  let Ref(hash) = ref
  receive_defs([
    #(identity.hash_to_debug_string(hash), bytes),
    #(identity.hash_to_debug_string(hash_bytes(<<"other">>)), <<"forged">>),
  ])
  |> should.be_error
  adapter.lookup(ref) |> should.equal(Ok(None))
}

pub fn pushed_batch_rejects_invalid_hex_test() {
  let _adapter = storage.inmemory()
  receive_defs([#("not-hex", <<"untrusted">>)]) |> should.be_error
}

pub fn definition_reopens_from_dets_test() {
  let path = scratch_path()
  let assert Ok(adapter) = storage.dets(path)
  let def = int_definition(97)
  let ref = Ref(codebase.hash_of_definition(def))
  let assert Ok(_) =
    codebase.insert(
      codebase.with_adapter(adapter),
      ast.Unit(ref, [#(ref, def)]),
    )
  adapter.close() |> should.equal(Ok(Nil))
  let assert Ok(reopened) = storage.dets(path)
  reopened.lookup(ref) |> should.equal(Ok(Some(encode_definition(def))))
  reopened.close() |> should.equal(Ok(Nil))
  storage.dets_delete_file(path) |> should.equal(Ok(Nil))
}

pub fn closed_dets_write_returns_error_test() {
  let path = scratch_path()
  let assert Ok(adapter) = storage.dets(path)
  adapter.close() |> should.equal(Ok(Nil))
  let def = int_definition(98)
  let ref = Ref(codebase.hash_of_definition(def))
  codebase.insert(codebase.with_adapter(adapter), ast.Unit(ref, [#(ref, def)]))
  |> should.be_error
  storage.dets_delete_file(path) |> should.equal(Ok(Nil))
}

pub fn function_requirements_are_part_of_identity_test() {
  let body = ast.Int(99)
  let pure_type = ast.Fn([], ast.Builtin(ast.IntType), ast.Required([]))
  let effect_type =
    ast.Fn([], ast.Builtin(ast.IntType), ast.Required([ast.ReqVar(0)]))
  codebase.hash_of_definition(ast.TermDef(body, pure_type))
  |> should.not_equal(
    codebase.hash_of_definition(ast.TermDef(body, effect_type)),
  )
}

pub fn unique_schema_is_bound_to_its_guid_test() {
  let first = ast.TypeDef(ast.Unique(Local(0), "same-guid", [], []))
  let second =
    ast.TypeDef(
      ast.Unique(Local(0), "same-guid", [], [
        ast.Constructor(Local(0), [ast.TypeRefBuiltin(ast.IntType)]),
      ]),
    )
  codebase.hash_of_definition(first)
  |> should.not_equal(codebase.hash_of_definition(second))
}
