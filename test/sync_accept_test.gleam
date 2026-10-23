import gleam/bit_array
import gleam/option.{None, Some}
import gleamunison/codebase
import gleamunison/identity.{Ref}
import gleamunison/sync
import gleamunison/sync_types.{type PeerId, HashConflict, PeerId, TransferFailed}
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

/// The admission guarantee the "sync bypasses the gate" worry is about: a
/// chunk whose bytes do not hash to the ref it claims is refused outright.
/// Content addressing is the gate here — a peer cannot poison the store by
/// naming its bytes something they are not, because the name IS the hash.
pub fn accept_chunk_rejects_bytes_that_do_not_match_their_ref_test() {
  let cb = codebase.empty()
  let honest = bit_array.from_string("the-real-definition")
  let ref = ref_for(honest)
  // The peer sends forged bytes under the honest ref, into an empty store.
  let forged = bit_array.from_string("something-else-entirely")
  let assert Error(TransferFailed(_, _)) =
    sync.accept_chunk(test_peer(), cb, ref, forged)
  // And nothing was admitted.
  codebase.get_adapter(cb).lookup(ref) |> should.equal(Ok(option.None))
}

/// A ref with no content behind it cannot be filled with arbitrary bytes:
/// the same check runs on the first write, not only on conflicts.
pub fn accept_chunk_verifies_even_the_first_write_test() {
  let cb = codebase.empty()
  let ref = Ref(identity.hash_bytes(bit_array.from_string("expected")))
  let assert Error(TransferFailed(_, _)) =
    sync.accept_chunk(test_peer(), cb, ref, bit_array.from_string("actual"))
  codebase.get_adapter(cb).lookup(ref) |> should.equal(Ok(option.None))
}
