import gleam/bit_array
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import gleamunison/ast
import gleamunison/codebase.{empty as new_codebase, hash_of_definition, insert}
import gleamunison/elab_types.{
  MissingAbilityDecl, SHandle, SInt, SurfaceTermDef, SurfaceUnit,
}
import gleamunison/elaborate as elab
import gleamunison/identity.{Ref, hash_bytes}
import gleamunison/storage
import gleamunison/sync.{new_sync_state, pull_sync}
import gleamunison/sync_types.{PeerId, TransferFailed}
import gleamunison/types.{empty_cache}
import gleeunit/should

@external(erlang, "gleamunison_tcp_sync", "start_link")
fn ffi_start_tcp_sync() -> Nil

@external(erlang, "gleamunison_tcp_sync", "get_port")
fn ffi_get_tcp_port() -> Int

pub fn pull_sync_over_tcp_test() {
  ffi_start_tcp_sync()
  let port = ffi_get_tcp_port()

  let def = ast.TermDef(ast.Int(42), ast.Builtin(ast.IntType))
  let ref = Ref(hash_of_definition(def))
  let unit = ast.Unit(ref, [#(ref, def)])
  let assert Ok(cb) = insert(new_codebase(), unit)
  let state = new_sync_state()

  let peer_name = "localhost:" <> int.to_string(port)
  let peer = PeerId(peer_name)

  case pull_sync(state, peer, cb) {
    Ok(#(_next_state, _cb, new_refs)) ->
      io.println(
        "Sync returned " <> int.to_string(list.length(new_refs)) <> " refs",
      )
    Error(e) ->
      io.println("Sync error (may be expected): " <> string.inspect(e))
  }
}

pub fn pull_sync_preserves_local_list_failure_test() {
  ffi_start_tcp_sync()
  let port = ffi_get_tcp_port()
  let peer = PeerId("localhost:" <> int.to_string(port))
  let adapter = storage.inmemory()
  let broken =
    storage.StorageAdapter(..adapter, list_refs: fn() {
      Error(storage.IoError("local list failed"))
    })
  pull_sync(new_sync_state(), peer, codebase.with_adapter(broken))
  |> should.equal(Error(TransferFailed(peer, "storage lookup failed")))
}

pub fn shandle_unknown_ability_errors_test() {
  let cache = empty_cache()
  let surface =
    SurfaceUnit(root: Ref(identity.hash_bytes(<<"root">>)), defs: [
      #(
        "my_term",
        SurfaceTermDef(SHandle(SInt(42), SInt(99), "NonExistentAbility")),
      ),
    ])
  let assert Error(MissingAbilityDecl("NonExistentAbility")) =
    elab.elaborate_unit(surface, cache)
}

@external(erlang, "gleamunison_ffi_io", "local_content_refs")
fn ffi_local_content_refs() -> List(String)

/// A store holds content and mutable pointers in the same key/value table. The
/// branch namespace and its head are pointers: their values are metadata and
/// their keys are not their hashes. Listing every key advertised those as
/// content, so a peer died in CAS admission on the first one and the documented
/// pull path could not complete against any store that had committed a name.
/// Evidence, by contrast, IS content and must keep travelling.
pub fn sync_offers_content_and_not_pointer_cells_test() {
  let def = ast.TermDef(ast.Int(7), ast.Builtin(ast.IntType))
  let ref = Ref(hash_of_definition(def))
  let assert Ok(cb) = insert(new_codebase(), ast.Unit(ref, [#(ref, def)]))
  let adapter = codebase.get_adapter(cb)

  // A branch pointer: metadata under a key that is not its hash. The adapter
  // is shared with these cells, so a key alone never proves content.
  let pointer_key = hash_bytes(<<"pointer-cell">>)
  let assert Ok(_) = adapter.insert(Ref(pointer_key), <<"head:1:bWFpbg">>)

  let advertised = ffi_local_content_refs()
  advertised
  |> list.contains(identity.hash_to_debug_string(hash_of_definition(def)))
  |> should.equal(True)
  advertised
  |> list.contains(identity.hash_to_debug_string(pointer_key))
  |> should.equal(False)
}

/// The other half of the same rule: an attestation is content, so a peer must
/// still be offered it. Filtering to definitions only would have "fixed"
/// admission by silently dropping the evidence `pkg install` gates on.
pub fn sync_offers_attestations_as_content_test() {
  let def = ast.TermDef(ast.Int(9), ast.Builtin(ast.IntType))
  let ref = Ref(hash_of_definition(def))
  let assert Ok(cb) = insert(new_codebase(), ast.Unit(ref, [#(ref, def)]))
  let adapter = codebase.get_adapter(cb)

  let attestation = <<"evidence:1:Z", 7, 8, 9>>
  let attestation_hash = hash_bytes(attestation)
  let assert Ok(_) = adapter.insert(Ref(attestation_hash), attestation)

  // A branch pointer: metadata under a key that is not its hash.
  let pointer_key = hash_bytes(<<"namespace-cell">>)
  let assert Ok(_) = adapter.insert(Ref(pointer_key), <<"ns\n1\nZm9v">>)

  let advertised = ffi_local_content_refs()
  advertised
  |> list.contains(identity.hash_to_debug_string(attestation_hash))
  |> should.equal(True)
  advertised
  |> list.contains(identity.hash_to_debug_string(pointer_key))
  |> should.equal(False)
}

/// A manifest closure is definitions and manifests. The attestations that admit
/// those definitions are separate content, so a peer installing by manifest
/// hash had nothing to satisfy its own evidence gate with and refused every
/// install — even though the peer held the records. Evidence travels by
/// subject, and every chunk still has to answer a ref we asked for.
pub fn evidence_is_fetched_by_subject_not_by_whole_store_test() {
  let def = ast.TermDef(ast.Int(11), ast.Builtin(ast.IntType))
  let ref = Ref(hash_of_definition(def))
  let assert Ok(cb) = insert(new_codebase(), ast.Unit(ref, [#(ref, def)]))
  let adapter = codebase.get_adapter(cb)

  // Two attestations, one relevant. The answer must name only the subject asked
  // for: a closure fetch moves the closure, not the peer's whole store.
  let wanted_subject = identity.hash_to_debug_string(hash_of_definition(def))
  let wanted = <<"evidence:1:", b64(wanted_subject):utf8, ":test:1:sig:note">>
  let other_subject = identity.hash_to_debug_string(hash_bytes(<<"other">>))
  let other = <<"evidence:1:", b64(other_subject):utf8, ":test:1:sig:note">>
  let assert Ok(_) = adapter.insert(Ref(hash_bytes(wanted)), wanted)
  let assert Ok(_) = adapter.insert(Ref(hash_bytes(other)), other)

  let records = ffi_evidence_for_subjects([wanted_subject])
  list.length(records) |> should.equal(1)
  let assert [#(hex, bytes)] = records
  hex |> should.equal(identity.hash_to_debug_string(hash_bytes(wanted)))
  bytes |> should.equal(wanted)
}

@external(erlang, "gleamunison_ffi_io", "evidence_for_subjects")
fn ffi_evidence_for_subjects(
  subjects: List(String),
) -> List(#(String, BitArray))

fn b64(value: String) -> String {
  bit_array.base64_encode(bit_array.from_string(value), True)
}
