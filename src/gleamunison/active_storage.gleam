//// Access to the one storage backend opened by this node.

import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/result
import gleam/string
import gleamunison/cli_lifecycle
import gleamunison/dynamic_ffi.{from_dynamic}
import gleamunison/identity.{
  type DefinitionRef, Ref, hash_from_bytes, hash_to_bytes,
}
import gleamunison/storage.{type StorageAdapter}

@external(erlang, "gleamunison_storage", "active")
fn active_ffi() -> Result(Dynamic, String)

pub type StorageBackend {
  Ets(BitArray)
  Dets(BitArray)
  PartitionedDets(BitArray)
  Mnesia(BitArray)
}

fn ref_bytes(ref: DefinitionRef) -> BitArray {
  let Ref(hash) = ref
  hash_to_bytes(hash)
}

fn refs(values: List(BitArray)) -> List(DefinitionRef) {
  list.map(values, fn(bytes) { Ref(hash_from_bytes(bytes)) })
}

/// Reuse the active backend; absent active storage, resolve the configured
/// default exactly as the HTTP server does. Shared backends are not closed here.
pub fn active_or_open() -> Result(StorageAdapter, String) {
  case active_ffi() {
    Ok(backend) -> Ok(adapter(from_dynamic(backend)))
    Error(_) -> {
      use path <- result.try(cli_lifecycle.resolve_store_path())
      storage.dets(path) |> result.map_error(string.inspect)
    }
  }
}

fn adapter(backend: StorageBackend) -> StorageAdapter {
  case backend {
    Ets(table) ->
      make(
        fn(ref, bytes) { storage.ffi_ets_insert(table, ref_bytes(ref), bytes) },
        fn(ref) { storage.ffi_ets_lookup(table, ref_bytes(ref)) },
        fn(ref) { storage.ffi_ets_delete(table, ref_bytes(ref)) },
        fn() { storage.ffi_ets_list_refs(table) |> result.map(refs) },
      )
    Dets(table) ->
      make(
        fn(ref, bytes) { storage.ffi_dets_insert(table, ref_bytes(ref), bytes) },
        fn(ref) { storage.ffi_dets_lookup(table, ref_bytes(ref)) },
        fn(ref) { storage.ffi_dets_delete(table, ref_bytes(ref)) },
        fn() { storage.ffi_dets_list_refs(table) |> result.map(refs) },
      )
    PartitionedDets(directory) ->
      make(
        fn(ref, bytes) {
          storage.ffi_partitioned_dets_insert(directory, ref_bytes(ref), bytes)
        },
        fn(ref) {
          storage.ffi_partitioned_dets_lookup(directory, ref_bytes(ref))
        },
        fn(ref) {
          storage.ffi_partitioned_dets_delete(directory, ref_bytes(ref))
        },
        fn() {
          storage.ffi_partitioned_dets_list_refs(directory) |> result.map(refs)
        },
      )
    Mnesia(table) ->
      make(
        fn(ref, bytes) {
          storage.ffi_mnesia_insert(table, ref_bytes(ref), bytes)
        },
        fn(ref) { storage.ffi_mnesia_lookup(table, ref_bytes(ref)) },
        fn(ref) { storage.ffi_mnesia_delete(table, ref_bytes(ref)) },
        fn() { storage.ffi_mnesia_list_refs(table) |> result.map(refs) },
      )
  }
}

fn make(insert, lookup, delete, list_refs) {
  storage.StorageAdapter(insert:, lookup:, delete:, list_refs:, close: fn() {
    Ok(Nil)
  })
}
