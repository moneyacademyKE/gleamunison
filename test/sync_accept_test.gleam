import gleam/bit_array
import gleam/option.{Some}
import gleamunison/codebase
import gleamunison/identity.{Ref}
import gleamunison/sync
import gleamunison/sync_types.{type PeerId, HashConflict, PeerId}
import gleeunit/should

fn test_peer() -> PeerId {
  PeerId("test:9")
}

fn ref_for(bytes: BitArray) {
  Ref(identity.hash_bytes(bytes))
}

pub fn accept_chunk_stores_fresh_chunk_test() {
  let cb = codebase.empty()
  let bytes = bit_array.from_string("def-bytes-1")
  let ref = ref_for(bytes)
  let assert Ok(cb2) = sync.accept_chunk(test_peer(), cb, ref, bytes)
  codebase.get_adapter(cb2).lookup(ref)
  |> should.be_ok
  |> should.equal(Some(bytes))
}

pub fn accept_chunk_idempotent_on_identical_bytes_test() {
  let cb = codebase.empty()
  let bytes = bit_array.from_string("def-bytes-2")
  let ref = ref_for(bytes)
  let assert Ok(cb) = sync.accept_chunk(test_peer(), cb, ref, bytes)
  // Same ref, same bytes: fine.
  let assert Ok(_) = sync.accept_chunk(test_peer(), cb, ref, bytes)
}

pub fn accept_chunk_rejects_conflicting_bytes_test() {
  let cb = codebase.empty()
  let bytes = bit_array.from_string("honest-def")
  let ref = ref_for(bytes)
  let assert Ok(cb) = sync.accept_chunk(test_peer(), cb, ref, bytes)
  // A peer sends different bytes under a ref we already hold: HashConflict.
  let forged = bit_array.from_string("forged-def")
  let assert Error(HashConflict(_, _, _, _)) =
    sync.accept_chunk(test_peer(), cb, ref, forged)
}

pub fn validate_chunk_set_rejects_unsolicited_chunks_test() {
  let requested = ["aaaa", "bbbb"]
  let assert Ok(Nil) =
    sync.validate_chunk_set(requested, [
      #("aaaa", <<>>),
      #("bbbb", <<>>),
    ])
  let assert Error(_) = sync.validate_chunk_set(requested, [#("cccc", <<>>)])
}
