import gleam/option.{type Option, None}
import gleamunison/identity.{type DefinitionRef}

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

pub fn inmemory() -> StorageAdapter {
  StorageAdapter(
    insert: fn(_ref, _bytes) { Ok(Nil) },
    lookup: fn(_ref) { Ok(None) },
    list_refs: fn() { Ok([]) },
  )
}
