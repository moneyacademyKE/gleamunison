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

/// Open a connection to a peer. Stays open for subsequent fetch_refs
/// batches — the selective-pull primitive's session handle.
pub fn connect(peer: PeerId) -> Result(Nil, SyncError) {
  let PeerId(name) = peer
  case sync_connect(name) {
    Ok(_) -> Ok(Nil)
    Error(_) -> Error(ConnectionFailed(peer, PeerNotFound(peer)))
  }
}

/// Verify the content binding even on the first write. Existing refs remain
/// byte-identical and storage errors are failures, never a missing value.
/// Legacy inspect-rendered definitions cannot be verified and fail closed.
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
        True ->
          codebase.insert_raw_checked(codebase, ref, bytes)
          |> result.map_error(fn(_) {
            TransferFailed(peer, "content admission failed")
          })
        False -> Error(HashConflict(peer, ref, existing, bytes))
      }
    Ok(_) ->
      codebase.insert_raw_checked(codebase, ref, bytes)
      |> result.map_error(fn(_) {
        TransferFailed(peer, "content admission failed")
      })
    Error(_) -> Error(TransferFailed(peer, "storage lookup failed"))
  }
}

/// Fetch exactly the given refs from an already-connected peer:
/// request, unsolicited-chunk validation, conflict-checked accept.
/// Returns the codebase with the chunks applied. This is the selective
/// transfer primitive: the caller computes the ref set (e.g. a package
/// manifest closure) and the wire moves nothing else.
pub fn fetch_refs(
  peer: PeerId,
  codebase: Codebase,
  hexes: List(String),
) -> Result(Codebase, SyncError) {
  let PeerId(name) = peer
  use Nil <- result.try(
    list.try_each(hexes, fn(hex) {
      identity.parse_ref_hex(hex)
      |> result.map(fn(_) { Nil })
      |> result.map_error(fn(msg) { TransferFailed(peer, msg) })
    }),
  )
  case sync_request_defs(name, hexes) {
    Error(msg) -> Error(TransferFailed(peer, msg))
    Ok(def_blobs) -> {
      use Nil <- result.try(validate_chunk_set(hexes, def_blobs))
      list.try_fold(def_blobs, codebase, fn(cb, pair) {
        let #(hash_hex, bytes) = pair
        use ref <- result.try(
          identity.parse_ref_hex(hash_hex)
          |> result.map_error(fn(msg) { TransferFailed(peer, msg) }),
        )
        accept_chunk(peer, cb, ref, bytes)
      })
    }
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
                      use ref <- result.try(
                        identity.parse_ref_hex(hash_hex)
                        |> result.map_error(fn(msg) {
                          TransferFailed(peer, msg)
                        }),
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
