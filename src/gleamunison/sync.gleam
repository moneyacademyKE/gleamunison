import gleam/dict
import gleam/list
import gleam/option.{Some}
import gleam/set
import gleam/string
import gleamunison/codebase.{type Codebase}
import gleamunison/identity.{type DefinitionRef, Ref, hash_to_debug_string}
import gleamunison/storage.{type StorageAdapter}
import gleamunison/sync_types.{
  type PeerId, type SyncError, type SyncState, Connected, ConnectionFailed,
  PeerId, PeerNotFound, PeerState, SyncState, TransferFailed, sync_connect,
  sync_push_defs, sync_receive_diff, sync_request_defs, sync_send_refs,
}
import gleamy/priority_queue

pub fn new_sync_state() -> SyncState {
  SyncState(peers: dict.new(), known_refs: set.new())
}

pub fn pull_sync(
  state: SyncState,
  peer: PeerId,
  codebase: Codebase,
) -> Result(#(SyncState, Codebase, List(DefinitionRef)), SyncError) {
  let PeerId(name) = peer
  case sync_connect(name) {
    Ok(_) -> {
      let our_refs = set.to_list(state.known_refs)
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
                  let compare_refs = fn(r1: DefinitionRef, r2: DefinitionRef) {
                    let Ref(h1) = r1
                    let Ref(h2) = r2
                    string.compare(
                      hash_to_debug_string(h1),
                      hash_to_debug_string(h2),
                    )
                  }
                  let pq = priority_queue.new(compare_refs)
                  let #(new_cb, next_pq) =
                    list.fold(def_blobs, #(codebase, pq), fn(acc, pair) {
                      let #(cb, q) = acc
                      let #(hash_hex, bytes) = pair
                      let ref =
                        identity.Ref(
                          identity.hash_from_bytes(identity.hex_to_bytes(
                            hash_hex,
                          )),
                        )
                      let next_cb = codebase.insert_raw(cb, ref, bytes)
                      #(next_cb, priority_queue.push(q, ref))
                    })
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
