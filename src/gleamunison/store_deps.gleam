//// Read-only compatibility queries plus checked retraction decisions.
//// Mutation callers build one verified snapshot and reuse it for all checks.

import gleam/list
import gleam/result
import gleam/string
import gleamunison/branch_scope
import gleamunison/dependency_snapshot
import gleamunison/identity.{type DefinitionRef, ref_hex as canonical_ref_hex}
import gleamunison/storage

const default_branch = "main"

pub type DependencyError {
  StoreFailure(storage.StorageError)
  NamespaceFailure(String)
  CorruptDefinition(DefinitionRef)
}

fn convert(error: dependency_snapshot.ScanError) -> DependencyError {
  case error {
    dependency_snapshot.StoreFailure(error) -> StoreFailure(error)
    dependency_snapshot.NamespaceFailure(reason) -> NamespaceFailure(reason)
    dependency_snapshot.CorruptDefinition(ref) -> CorruptDefinition(ref)
  }
}

pub fn describe_dependency_error(error: DependencyError) -> String {
  case error {
    StoreFailure(error) -> storage.describe_error(error)
    NamespaceFailure(reason) -> reason
    CorruptDefinition(ref) -> "corrupt or unreadable definition " <> hex(ref)
  }
}

pub fn dependents_checked(
  adapter: storage.StorageAdapter,
  target: DefinitionRef,
) -> Result(List(DefinitionRef), DependencyError) {
  dependents_checked_on_branch(adapter, default_branch, target)
}

pub fn dependents_checked_on_branch(
  adapter: storage.StorageAdapter,
  branch: String,
  target: DefinitionRef,
) -> Result(List(DefinitionRef), DependencyError) {
  dependency_snapshot.read(adapter, branch)
  |> result.map(fn(snapshot) {
    dependency_snapshot.dependents(snapshot, target)
  })
  |> result.map_error(convert)
}

pub fn other_names_checked(
  adapter: storage.StorageAdapter,
  target: DefinitionRef,
  retracting: String,
) -> Result(List(String), DependencyError) {
  other_names_checked_on_branch(adapter, default_branch, target, retracting)
}

pub fn other_names_checked_on_branch(
  adapter: storage.StorageAdapter,
  branch: String,
  target: DefinitionRef,
  retracting: String,
) -> Result(List(String), DependencyError) {
  dependency_snapshot.read(adapter, branch)
  |> result.map(fn(snapshot) {
    dependency_snapshot.names(snapshot, target)
    |> list.filter(fn(name) { name != retracting })
  })
  |> result.map_error(convert)
}

pub fn exclusive_closure_checked(
  adapter: storage.StorageAdapter,
  root: DefinitionRef,
) -> Result(List(DefinitionRef), DependencyError) {
  exclusive_closure_checked_on_branch(adapter, default_branch, root)
}

pub fn exclusive_closure_checked_on_branch(
  adapter: storage.StorageAdapter,
  branch: String,
  root: DefinitionRef,
) -> Result(List(DefinitionRef), DependencyError) {
  dependency_snapshot.read(adapter, branch)
  |> result.map(fn(snapshot) {
    dependency_snapshot.exclusive_closure(snapshot, root)
  })
  |> result.map_error(convert)
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

pub fn hex(ref: DefinitionRef) -> String {
  canonical_ref_hex(ref)
}
