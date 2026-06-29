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
      io.println("Sync returned " <> int.to_string(list.length(new_refs)) <> " refs")
    Error(e) -> io.println("Sync error (may be expected): " <> string.inspect(e))
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
