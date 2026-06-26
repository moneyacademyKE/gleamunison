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
  )
}

// FFI to Erlang ETS storage module
@external(erlang, "gleamunison_storage", "new")
fn ffi_new() -> BitArray

@external(erlang, "gleamunison_storage", "insert")
fn ffi_insert(tab: BitArray, ref: BitArray, bytes: BitArray) -> Result(Nil, StorageError)

@external(erlang, "gleamunison_storage", "lookup")
fn ffi_lookup(tab: BitArray, ref: BitArray) -> Result(Option(BitArray), StorageError)

@external(erlang, "gleamunison_storage", "list_refs")
fn ffi_list_refs(tab: BitArray) -> Result(List(BitArray), StorageError)

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
  )
}
