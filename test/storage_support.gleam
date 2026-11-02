//// Test-only storage helpers, relocated from src (bk-e431).
////
//// `check_content` and the `partitioned_dets` adapter constructor had zero
//// production callers: tests drive the erl backend through them directly.
//// Bodies are verbatim from src/gleamunison/storage.gleam; only the
//// open/close externals moved to `test_ffi` alongside.

import gleam/list
import gleam/option.{None, Some}
import gleamunison/identity.{
  type DefinitionRef, Ref, hash_from_bytes, hash_to_bytes,
}
import gleamunison/storage.{
  type StorageAdapter, type StorageError, NotFound, StorageAdapter,
  ffi_partitioned_dets_delete, ffi_partitioned_dets_insert,
  ffi_partitioned_dets_list_refs, ffi_partitioned_dets_lookup, verify_content,
}
import test_ffi

/// Check a known immutable ref. Mutable pointer cells are not CAS content.
pub fn check_content(
  adapter: StorageAdapter,
  ref: DefinitionRef,
) -> Result(Nil, StorageError) {
  case adapter.lookup(ref) {
    Ok(Some(bytes)) -> verify_content(ref, bytes)
    Ok(None) -> Error(NotFound)
    Error(error) -> Error(error)
  }
}

/// Partitioned DETS adapter: per-ref ffi externals stay in `storage`
/// (production calls them via active_storage); open/close are test_ffi.
pub fn partitioned_dets(
  dir_path: String,
) -> Result(StorageAdapter, StorageError) {
  case test_ffi.partitioned_dets_new(dir_path) {
    Ok(tab) -> {
      Ok(
        StorageAdapter(
          insert: fn(ref, bytes) {
            let Ref(h) = ref
            ffi_partitioned_dets_insert(tab, hash_to_bytes(h), bytes)
          },
          lookup: fn(ref) {
            let Ref(h) = ref
            ffi_partitioned_dets_lookup(tab, hash_to_bytes(h))
          },
          delete: fn(ref) {
            let Ref(h) = ref
            ffi_partitioned_dets_delete(tab, hash_to_bytes(h))
          },
          list_refs: fn() {
            case ffi_partitioned_dets_list_refs(tab) {
              Ok(lst) -> Ok(list.map(lst, fn(b) { Ref(hash_from_bytes(b)) }))
              Error(e) -> Error(e)
            }
          },
          close: fn() { test_ffi.partitioned_dets_close(tab) },
        ),
      )
    }
    Error(e) -> Error(e)
  }
}
