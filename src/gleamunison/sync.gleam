import gleam/dict
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/set
import gleam/string
import gleamunison/codebase.{type Codebase, list_refs}
import gleamunison/identity.{type DefinitionRef, Ref, hash_to_debug_string}
import gleamunison/storage.{type StorageAdapter}
import gleamunison/sync_types.{
  type PeerId, type SyncError, type SyncState, Connected, ConnectionFailed,
  HashConflict, PeerId, PeerNotFound, PeerState, SyncState, TransferFailed,
  sync_connect, sync_push_defs, sync_receive_diff, sync_request_defs,
  sync_send_refs,
}
import gleamy/priority_queue

pub fn new_sync_state() -> SyncState {
  SyncState(peers: dict.new(), known_refs: set.new())
}

/// Accept one chunk from a peer under CAS discipline: a ref already held
/// must map to byte-identical content — first write wins, and any later
/// conflicting bytes for the same ref are a HashConflict, never an
/// overwrite. Fresh refs store raw. This is the check that makes "content-
/// addressed" mean something on the wire: once any honest peer's bytes
/// land, no peer can rewrite that ref's binding.
///
/// Known boundary: storage holds inspect-rendered bytes whose structural
/// hash cannot be recomputed from the bytes alone, so a *first* write
/// still trusts the sender. Full binding needs canonical serialization
/// (the known debug-serialization debt); until then, consistency pinning
/// is the honest check with teeth.
pub fn accept_chunk(
  peer: PeerId,
  codebase: Codebase,
  ref: DefinitionRef,
  bytes: BitArray,
) -> Result(Codebase, SyncError) {
  let adapter = codebase.get_adapter(codebase)
  case adapter.lookup(ref) {
    Ok(Some(existing)) ->
      case existing == bytes {
        // idempotent: same content-addressed content
        True -> Ok(codebase)
        False -> Error(HashConflict(peer, ref, existing, bytes))
      }
    _ -> Ok(codebase.insert_raw(codebase, ref, bytes))
  }
}

/// Every received chunk must answer a ref we actually asked for. A peer
/// sending unsolicited chunks fails the transfer loudly.
pub fn validate_chunk_set(
  requested: List(String),
  received: List(#(String, BitArray)),
) -> Result(Nil, SyncError) {
  let requested_set = set.from_list(requested)
  let unsolicited =
    list.filter(received, fn(pair) { !set.contains(requested_set, pair.0) })
  case unsolicited {
    [] -> Ok(Nil)
    [#(hex, _), ..] ->
      Error(TransferFailed(PeerId("remote"), "unsolicited chunk: " <> hex))
  }
}

pub fn pull_sync(
  state: SyncState,
  peer: PeerId,
  codebase: Codebase,
) -> Result(#(SyncState, Codebase, List(DefinitionRef)), SyncError) {
  let PeerId(name) = peer
  case sync_connect(name) {
    Ok(_) -> {
      let our_refs =
        set.to_list(set.union(
          state.known_refs,
          set.from_list(list_refs(codebase)),
        ))
      let ref_strings =
        list.map(our_refs, fn(r) {
          let Ref(h) = r
          hash_to_debug_string(h)
        })
      case sync_send_refs(name, ref_strings) {
        Ok(_) -> {
          case sync_receive_diff(name) {
            Ok(diff_refs) -> {
              case sync_request_defs(name, diff_refs) {
                Ok(def_blobs) -> {
                  use Nil <- result.try(validate_chunk_set(diff_refs, def_blobs))
                  let compare_refs = fn(r1: DefinitionRef, r2: DefinitionRef) {
                    let Ref(h1) = r1
                    let Ref(h2) = r2
                    string.compare(
                      hash_to_debug_string(h1),
                      hash_to_debug_string(h2),
                    )
                  }
                  let pq = priority_queue.new(compare_refs)
                  let accept =
                    list.try_fold(def_blobs, #(codebase, pq), fn(acc, pair) {
                      let #(cb, q) = acc
                      let #(hash_hex, bytes) = pair
                      let ref =
                        identity.Ref(
                          identity.hash_from_bytes(identity.hex_to_bytes(
                            hash_hex,
                          )),
                        )
                      case accept_chunk(peer, cb, ref, bytes) {
                        Ok(next_cb) ->
                          Ok(#(next_cb, priority_queue.push(q, ref)))
                        Error(e) -> Error(e)
                      }
                    })
                  case accept {
                    Error(e) -> Error(e)
                    Ok(#(new_cb, next_pq)) -> {
                      let new_refs = priority_queue.to_list(next_pq)
                      let ps =
                        PeerState(
                          last_seen: 1,
                          refs: set.from_list(our_refs),
                          status: Connected,
                        )
                      let new_peers = dict.insert(state.peers, peer, ps)
                      let new_known =
                        set.union(state.known_refs, set.from_list(new_refs))
                      Ok(#(
                        SyncState(peers: new_peers, known_refs: new_known),
                        new_cb,
                        new_refs,
                      ))
                    }
                  }
                }
                Error(msg) -> Error(TransferFailed(peer, msg))
              }
            }
            Error(msg) -> Error(TransferFailed(peer, msg))
          }
        }
        Error(msg) -> Error(TransferFailed(peer, msg))
      }
    }
    Error(_) -> Error(ConnectionFailed(peer, PeerNotFound(peer)))
  }
}

pub fn push_sync(
  state: SyncState,
  peer: PeerId,
  refs: List(DefinitionRef),
  adapter: StorageAdapter,
) -> Result(#(SyncState, Int), SyncError) {
  let PeerId(name) = peer
  case sync_connect(name) {
    Ok(_) -> {
      let blobs =
        list.filter_map(refs, fn(r) {
          case adapter.lookup(r) {
            Ok(Some(bytes)) -> {
              let Ref(h) = r
              Ok(#(hash_to_debug_string(h), bytes))
            }
            _ -> Error(Nil)
          }
        })
      case sync_push_defs(name, blobs) {
        Ok(_) -> Ok(#(state, list.length(blobs)))
        Error(msg) -> Error(TransferFailed(peer, msg))
      }
    }
    Error(_) -> Error(ConnectionFailed(peer, PeerNotFound(peer)))
  }
}
