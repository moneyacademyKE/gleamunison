//// Name references resolved through one immutable selected-branch view.

import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleamunison/identity.{type DefinitionRef}
import gleamunison/namespace
import gleamunison/repl_eval
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

/// Whether the branch binds this content under any name.
///
/// A content hash is the same on every branch — the branch selects how
/// *dependencies* resolve, never a version of the target. So this answers a
/// question the caller still needs answered: did `--branch` actually name this
/// content, or only the names around it? Silence there is what let a typo'd
/// branch look applied.
pub fn binds_content(bindings: Bindings, ref: DefinitionRef) -> Bool {
  dict.values(bindings) |> list.any(fn(content) { content == ref })
}

pub fn from_namespace(ns: namespace.Namespace) -> Bindings {
  dict.from_list(
    list.map(namespace.names(ns), fn(name) {
      let assert Ok(content) = namespace.get(ns, name)
      #(repl_eval.ref_for_name(name), content)
    }),
  )
}
