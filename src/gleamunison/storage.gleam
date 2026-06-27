import gleam/list
import gleam/option.{type Option}
import gleamunison/identity.{type DefinitionRef, Ref, hash_from_bytes, hash_to_bytes}

pub type StorageError {
  StorageError(message: String)
  NotFound
  IoError(reason: String)
}

pub type StorageAdapter {
  StorageAdapter(
    insert: fn(DefinitionRef, BitArray) -> Result(Nil, StorageError),
    lookup: fn(DefinitionRef) -> Result(Option(BitArray), StorageError),
    list_refs: fn() -> Result(List(DefinitionRef), StorageError),
    close: fn() -> Result(Nil, StorageError),
  )
}

@external(erlang, "gleamunison_storage", "new")
fn ffi_new() -> BitArray

@external(erlang, "gleamunison_storage", "insert")
fn ffi_insert(tab: BitArray, ref: BitArray, bytes: BitArray) -> Result(Nil, StorageError)

@external(erlang, "gleamunison_storage", "lookup")
fn ffi_lookup(tab: BitArray, ref: BitArray) -> Result(Option(BitArray), StorageError)

@external(erlang, "gleamunison_storage", "list_refs")
fn ffi_list_refs(tab: BitArray) -> Result(List(BitArray), StorageError)

@external(erlang, "gleamunison_storage", "dets_new")
fn ffi_dets_new(path: String) -> Result(BitArray, StorageError)

@external(erlang, "gleamunison_storage", "dets_insert")
fn ffi_dets_insert(tab: BitArray, ref: BitArray, bytes: BitArray) -> Result(Nil, StorageError)

@external(erlang, "gleamunison_storage", "dets_lookup")
fn ffi_dets_lookup(tab: BitArray, ref: BitArray) -> Result(Option(BitArray), StorageError)

@external(erlang, "gleamunison_storage", "dets_list_refs")
fn ffi_dets_list_refs(tab: BitArray) -> Result(List(BitArray), StorageError)

@external(erlang, "gleamunison_storage", "dets_close")
fn ffi_dets_close(tab: BitArray) -> Result(Nil, StorageError)

@external(erlang, "gleamunison_storage", "dets_delete_file")
pub fn dets_delete_file(path: String) -> Result(Nil, StorageError)

@external(erlang, "gleamunison_storage", "partitioned_dets_new")
fn ffi_partitioned_dets_new(dir_path: String) -> Result(BitArray, StorageError)

@external(erlang, "gleamunison_storage", "partitioned_dets_insert")
fn ffi_partitioned_dets_insert(tab: BitArray, ref: BitArray, bytes: BitArray) -> Result(Nil, StorageError)

@external(erlang, "gleamunison_storage", "partitioned_dets_lookup")
fn ffi_partitioned_dets_lookup(tab: BitArray, ref: BitArray) -> Result(Option(BitArray), StorageError)

@external(erlang, "gleamunison_storage", "partitioned_dets_list_refs")
fn ffi_partitioned_dets_list_refs(tab: BitArray) -> Result(List(BitArray), StorageError)

@external(erlang, "gleamunison_storage", "partitioned_dets_close")
fn ffi_partitioned_dets_close(tab: BitArray) -> Result(Nil, StorageError)

@external(erlang, "gleamunison_storage", "partitioned_dets_delete_file")
pub fn partitioned_dets_delete(dir_path: String) -> Result(Nil, StorageError)

@external(erlang, "gleamunison_storage", "mnesia_new")
fn ffi_mnesia_new(table_name: String) -> Result(BitArray, StorageError)

@external(erlang, "gleamunison_storage", "mnesia_insert")
fn ffi_mnesia_insert(tab: BitArray, ref: BitArray, bytes: BitArray) -> Result(Nil, StorageError)

@external(erlang, "gleamunison_storage", "mnesia_lookup")
fn ffi_mnesia_lookup(tab: BitArray, ref: BitArray) -> Result(Option(BitArray), StorageError)

@external(erlang, "gleamunison_storage", "mnesia_list_refs")
fn ffi_mnesia_list_refs(tab: BitArray) -> Result(List(BitArray), StorageError)

@external(erlang, "gleamunison_storage", "mnesia_close")
fn ffi_mnesia_close(tab: BitArray) -> Result(Nil, StorageError)

pub fn inmemory() -> StorageAdapter {
  let tab = ffi_new()
  StorageAdapter(
    insert: fn(ref, bytes) {
      let Ref(h) = ref
      ffi_insert(tab, hash_to_bytes(h), bytes)
    },
    lookup: fn(ref) {
      let Ref(h) = ref
      ffi_lookup(tab, hash_to_bytes(h))
    },
    list_refs: fn() {
      case ffi_list_refs(tab) {
        Ok(lst) -> Ok(list.map(lst, fn(b) { Ref(hash_from_bytes(b)) }))
        Error(e) -> Error(e)
      }
    },
    close: fn() { Ok(Nil) },
  )
}

pub fn dets(path: String) -> Result(StorageAdapter, StorageError) {
  case ffi_dets_new(path) {
    Ok(tab) -> {
      Ok(StorageAdapter(
        insert: fn(ref, bytes) {
          let Ref(h) = ref
          ffi_dets_insert(tab, hash_to_bytes(h), bytes)
        },
        lookup: fn(ref) {
          let Ref(h) = ref
          ffi_dets_lookup(tab, hash_to_bytes(h))
        },
        list_refs: fn() {
          case ffi_dets_list_refs(tab) {
            Ok(lst) -> Ok(list.map(lst, fn(b) { Ref(hash_from_bytes(b)) }))
            Error(e) -> Error(e)
          }
        },
        close: fn() { ffi_dets_close(tab) },
      ))
    }
    Error(e) -> Error(e)
  }
}

pub fn partitioned_dets(dir_path: String) -> Result(StorageAdapter, StorageError) {
  case ffi_partitioned_dets_new(dir_path) {
    Ok(tab) -> {
      Ok(StorageAdapter(
        insert: fn(ref, bytes) {
          let Ref(h) = ref
          ffi_partitioned_dets_insert(tab, hash_to_bytes(h), bytes)
        },
        lookup: fn(ref) {
          let Ref(h) = ref
          ffi_partitioned_dets_lookup(tab, hash_to_bytes(h))
        },
        list_refs: fn() {
          case ffi_partitioned_dets_list_refs(tab) {
            Ok(lst) -> Ok(list.map(lst, fn(b) { Ref(hash_from_bytes(b)) }))
            Error(e) -> Error(e)
          }
        },
        close: fn() { ffi_partitioned_dets_close(tab) },
      ))
    }
    Error(e) -> Error(e)
  }
}

pub fn mnesia(table_name: String) -> Result(StorageAdapter, StorageError) {
  case ffi_mnesia_new(table_name) {
    Ok(tab) -> {
      Ok(StorageAdapter(
        insert: fn(ref, bytes) {
          let Ref(h) = ref
          ffi_mnesia_insert(tab, hash_to_bytes(h), bytes)
        },
        lookup: fn(ref) {
          let Ref(h) = ref
          ffi_mnesia_lookup(tab, hash_to_bytes(h))
        },
        list_refs: fn() {
          case ffi_mnesia_list_refs(tab) {
            Ok(lst) -> Ok(list.map(lst, fn(b) { Ref(hash_from_bytes(b)) }))
            Error(e) -> Error(e)
          }
        },
        close: fn() { ffi_mnesia_close(tab) },
      ))
    }
    Error(e) -> Error(e)
  }
}
