//// Name references resolved through one immutable selected-branch view.

import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleamunison/identity.{type DefinitionRef}
import gleamunison/namespace
import gleamunison/storage

pub type Bindings =
  Dict(DefinitionRef, DefinitionRef)

pub fn read(
  adapter: storage.StorageAdapter,
  branch: String,
) -> Result(Bindings, String) {
  use ns <- result.try(namespace.load_current_or_empty(adapter, branch))
  Ok(from_namespace(ns))
}

pub fn from_namespace(ns: namespace.Namespace) -> Bindings {
  dict.from_list(
    list.map(namespace.names(ns), fn(name) {
      let assert Ok(content) = namespace.get(ns, name)
      #(identity.name_ref(name), content)
    }),
  )
}
