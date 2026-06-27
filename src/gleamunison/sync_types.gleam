import gleam/dict.{type Dict}
import gleam/set.{type Set}
import gleamunison/identity.{type DefinitionRef}

@external(erlang, "gleamunison_ffi_io", "sync_connect")
pub fn sync_connect(node: String) -> Result(Nil, String)

@external(erlang, "gleamunison_ffi_io", "sync_send_refs")
pub fn sync_send_refs(node: String, refs: List(String)) -> Result(Nil, String)

@external(erlang, "gleamunison_ffi_io", "sync_receive_diff")
pub fn sync_receive_diff(node: String) -> Result(List(String), String)

@external(erlang, "gleamunison_ffi_io", "sync_request_defs")
pub fn sync_request_defs(node: String, refs: List(String)) -> Result(List(#(String, BitArray)), String)

@external(erlang, "gleamunison_ffi_io", "sync_push_defs")
pub fn sync_push_defs(node: String, defs: List(#(String, BitArray))) -> Result(Nil, String)

pub type PeerId {
  PeerId(name: String)
}

pub type ConnectError {
  PeerNotFound(PeerId)
  CookieMismatch(PeerId)
  Timeout(PeerId)
  Refused(PeerId, reason: String)
}

pub type SyncError {
  ConnectionFailed(PeerId, ConnectError)
  TransferFailed(PeerId, message: String)
  HashConflict(PeerId, ref: DefinitionRef, local: BitArray, remote: BitArray)
}

pub type SyncState {
  SyncState(peers: Dict(PeerId, PeerState), known_refs: Set(DefinitionRef))
}

pub type PeerState {
  PeerState(last_seen: Int, refs: Set(DefinitionRef), status: PeerStatus)
}

pub type PeerStatus {
  Connected
  Disconnected
  Syncing
  Failed(String)
}
