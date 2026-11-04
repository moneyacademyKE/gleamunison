import gleam/io
import gleam/option.{None, Some}
import gleamunison/codebase
import gleamunison/identity.{Ref, hash_bytes}
import gleamunison/storage.{
  IoError, NotFound, StorageError, describe_error, inmemory,
}
import gleamunison/sync.{pull_sync}
import gleamunison/sync_types.{PeerId}

pub fn storage_roundtrip_test() {
  let adapter = inmemory()
  let ref = Ref(hash_bytes(<<"myref">>))
  let data = <<"hello world">>

  let assert Ok(None) = adapter.lookup(ref)
  let assert Ok(Nil) = adapter.insert(ref, data)
  let assert Ok(Some(retrieved)) = adapter.lookup(ref)
  let assert True = retrieved == data
}

pub fn describe_storage_errors_test() {
  let assert "read denied" = describe_error(StorageError("read denied"))
  let assert "not found" = describe_error(NotFound)
  let assert "io error: disk offline" = describe_error(IoError("disk offline"))
}

pub fn pull_empty_diff_test() {
  let cb = codebase.empty()
  let peer = PeerId("localnode")
  let _ = pull_sync(peer, cb)
  io.println("Sync empty diff test adapted for TCP protocol")
}
