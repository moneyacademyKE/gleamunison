//// Checked retraction decisions: the dependency error vocabulary and the
//// branch-binding queries the retraction commands share. Mutation callers
//// build ONE verified snapshot (dependency_snapshot.read) and reuse it for
//// all checks — the one-shot `*_checked` wrappers that used to live here
//// re-read the whole store per question, existed only for tests, and are
//// deleted (bk-f7ea); tests now use the production shape directly.

import gleam/list
import gleam/result
import gleam/string
import gleamunison/branch_scope
import gleamunison/identity.{type DefinitionRef, ref_hex as canonical_ref_hex}
import gleamunison/storage

pub type DependencyError {
  StoreFailure(storage.StorageError)
  NamespaceFailure(String)
  CorruptDefinition(DefinitionRef)
}

pub fn describe_dependency_error(error: DependencyError) -> String {
  case error {
    StoreFailure(error) -> storage.describe_error(error)
    NamespaceFailure(reason) -> reason
    CorruptDefinition(ref) ->
      "corrupt or unreadable definition " <> canonical_ref_hex(ref)
  }
}

/// Content is shared by every branch, so a retraction decision needs to know
/// whether a branch other than the selected one still binds the ref: deleting
/// bytes another branch resolves to leaves a binding nobody can load.
pub fn branches_binding_elsewhere(
  adapter: storage.StorageAdapter,
  ref: DefinitionRef,
  selected: String,
) -> Result(List(#(String, String)), DependencyError) {
  branch_scope.branches_binding(adapter, ref)
  |> result.map(fn(found) {
    list.filter(found, fn(pair) { pair.0 != selected })
  })
  |> result.map_error(NamespaceFailure)
}

/// `dev (a), feature (b)`: which branch holds it, and under what names.
/// One spelling of the refusal, so both retraction commands name the same
/// thing the same way.
pub fn describe_branch_bindings(held: List(#(String, String))) -> String {
  held
  |> list.fold([], fn(acc: List(#(String, String)), pair) {
    case list.find(acc, fn(entry) { entry.0 == pair.0 }) {
      Ok(_) ->
        list.map(acc, fn(entry) {
          case entry.0 == pair.0 {
            True -> #(entry.0, entry.1 <> ", " <> pair.1)
            False -> entry
          }
        })
      Error(_) -> list.append(acc, [pair])
    }
  })
  |> list.map(fn(entry) { entry.0 <> " (" <> entry.1 <> ")" })
  |> string.join(", ")
}
