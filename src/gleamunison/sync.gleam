import gleam/dict
import gleam/list
import gleam/option.{Some}
import gleam/set
import gleamunison/identity.{type DefinitionRef, Ref, hash_to_debug_string}
import gleamunison/codebase.{type Codebase}
import gleamunison/storage.{type StorageAdapter}
import gleamunison/sync_types.{
  type SyncState, type SyncError, type PeerId, SyncState, PeerId, PeerState, Connected, PeerNotFound, ConnectionFailed, TransferFailed,
  sync_connect, sync_send_refs, sync_request_defs, sync_push_defs
}

pub fn new_sync_state() -> SyncState {
  SyncState(peers: dict.new(), known_refs: set.new())
}

pub fn pull_sync(state: SyncState, peer: PeerId, _codebase: Codebase) -> Result(#(SyncState, List(DefinitionRef)), SyncError) {
  let PeerId(name) = peer
  case sync_connect(name) {
    Ok(_) -> {
      let our_refs = set.to_list(state.known_refs)
      let ref_strings = list.map(our_refs, fn(r) {
        let Ref(h) = r
        hash_to_debug_string(h)
      })
      case sync_send_refs(name, ref_strings) {
        Ok(_) -> {
          case sync_request_defs(name, ref_strings) {
            Ok(def_blobs) -> {
              let new_refs = list.filter_map(def_blobs, fn(blob) {
                Ok(identity.Ref(identity.hash_from_bytes(blob)))
              })
              let ps = PeerState(last_seen: 1, refs: set.from_list(our_refs), status: Connected)
              let new_peers = dict.insert(state.peers, peer, ps)
              let new_known = set.union(state.known_refs, set.from_list(new_refs))
              Ok(#(SyncState(peers: new_peers, known_refs: new_known), new_refs))
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

pub fn push_sync(state: SyncState, peer: PeerId, refs: List(DefinitionRef), adapter: StorageAdapter) -> Result(#(SyncState, Int), SyncError) {
  let PeerId(name) = peer
  case sync_connect(name) {
    Ok(_) -> {
      let blobs = list.filter_map(refs, fn(r) {
        case adapter.lookup(r) {
          Ok(Some(bytes)) -> Ok(bytes)
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
