import gleamunison/identity.{Ref, hash_to_debug_string}
import gleamunison/elab_types.{
  SurfaceUnit, SurfaceTermDef, SHandle, SInt, MissingAbilityDecl
}
import gleamunison/elaborate as elab
import gleamunison/types.{empty_cache}
import gleamunison/codebase
import gleamunison/sync.{pull_sync, new_sync_state}
import gleamunison/sync_types.{PeerId}

pub fn pull_sync_uses_hash_not_blob_test() {
  let cb = codebase.empty()
  let state = new_sync_state()
  let peer = PeerId("test_node")
  
  // Under the old code, this would fail because ffi returns [{ "01020304", "dummy_blob" }]
  // and we'd hash "dummy_blob" (result is NOT 01020304).
  // Under the new code, we decode the hex "01020304" and use it as the ref hash.
  let assert Ok(#(_next_state, _cb, [new_ref])) = pull_sync(state, peer, cb)
  let Ref(h) = new_ref
  let assert "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20" = hash_to_debug_string(h)
}

pub fn shandle_unknown_ability_errors_test() {
  let cache = empty_cache()
  // SHandle(SInt(42), SInt(99), "NonExistentAbility")
  let surface = SurfaceUnit(
    root: Ref(identity.hash_bytes(<<"root">>)),
    defs: [#("my_term", SurfaceTermDef(SHandle(SInt(42), SInt(99), "NonExistentAbility")))]
  )
  let assert Error(MissingAbilityDecl("NonExistentAbility")) = elab.elaborate_unit(surface, cache)
}
