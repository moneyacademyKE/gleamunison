import gleam/option.{Some, None}
import gleamunison/identity.{Ref, hash_bytes}
import gleamunison/storage.{inmemory}
import gleamunison/sync.{pull_sync, new_sync_state}
import gleamunison/sync_types.{PeerId}
import gleamunison/codebase

pub fn storage_roundtrip_test() {
  let adapter = inmemory()
  let ref = Ref(hash_bytes(<<"myref">>))
  let data = <<"hello world">>
  
  let assert Ok(None) = adapter.lookup(ref)
  let assert Ok(Nil) = adapter.insert(ref, data)
  let assert Ok(Some(retrieved)) = adapter.lookup(ref)
  let assert True = retrieved == data
}

pub fn pull_empty_diff_test() {
  let cb = codebase.empty()
  let state = new_sync_state()
  let peer = PeerId("localnode")
  let assert Ok(#(_next_state, _cb, new_refs)) = pull_sync(state, peer, cb)
  let assert [] = new_refs
}
