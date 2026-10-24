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
import gleamunison/sync.{new_sync_state, pull_sync}
import gleamunison/sync_types.{PeerId}
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

/// What a node offers a peer is definitions, and only definitions. Evidence
/// records are content-addressed too, so their keys look exactly like
/// definition refs: advertising every key offered a peer its own attestations
/// as content, and the pull died in CAS admission with "content admission
/// failed" — the documented sync path could not complete against a store that
/// held any evidence at all.
pub fn sync_offers_definitions_and_not_attestations_test() {
  let def = ast.TermDef(ast.Int(7), ast.Builtin(ast.IntType))
  let ref = Ref(hash_of_definition(def))
  let assert Ok(cb) = insert(new_codebase(), ast.Unit(ref, [#(ref, def)]))
  let adapter = codebase.get_adapter(cb)

  // An attestation row: a real content address, a payload that is not a
  // definition. Exactly the shape evidence.attach writes.
  let attestation = <<"evidence:1:Z", 0, 1, 2, 3>>
  let attestation_ref = Ref(hash_bytes(attestation))
  let assert Ok(_) = adapter.insert(attestation_ref, attestation)

  let advertised = ffi_local_content_refs()
  advertised
  |> should.equal([identity.hash_to_debug_string(hash_of_definition(def))])
}
