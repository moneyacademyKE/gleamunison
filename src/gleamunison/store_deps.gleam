//// Read-only compatibility queries plus checked retraction decisions.
//// Mutation callers build one verified snapshot and reuse it for all checks.

import gleam/list
import gleam/result
import gleamunison/dependency_snapshot
import gleamunison/identity.{type DefinitionRef, Ref, hash_to_debug_string}
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
    StoreFailure(error) -> string_error(error)
    NamespaceFailure(reason) -> reason
    CorruptDefinition(ref) -> "corrupt or unreadable definition " <> hex(ref)
  }
}

fn string_error(error: storage.StorageError) -> String {
  case error {
    storage.StorageError(message) -> message
    storage.NotFound -> "not found"
    storage.IoError(reason) -> "io error: " <> reason
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

/// Read-only legacy shape. Retraction must use read/checked queries instead.
pub fn dependents(
  adapter: storage.StorageAdapter,
  target: DefinitionRef,
) -> List(DefinitionRef) {
  dependents_on_branch(adapter, default_branch, target)
}

pub fn dependents_on_branch(
  adapter: storage.StorageAdapter,
  branch: String,
  target: DefinitionRef,
) -> List(DefinitionRef) {
  dependents_checked_on_branch(adapter, branch, target) |> result.unwrap([])
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

pub fn other_names(
  adapter: storage.StorageAdapter,
  target: DefinitionRef,
  retracting: String,
) -> List(String) {
  other_names_on_branch(adapter, default_branch, target, retracting)
}

pub fn other_names_on_branch(
  adapter: storage.StorageAdapter,
  branch: String,
  target: DefinitionRef,
  retracting: String,
) -> List(String) {
  other_names_checked_on_branch(adapter, branch, target, retracting)
  |> result.unwrap([])
}

pub fn stored_dependencies(
  adapter: storage.StorageAdapter,
  ref: DefinitionRef,
) -> List(DefinitionRef) {
  stored_dependencies_on_branch(adapter, default_branch, ref)
}

pub fn stored_dependencies_on_branch(
  adapter: storage.StorageAdapter,
  branch: String,
  ref: DefinitionRef,
) -> List(DefinitionRef) {
  dependency_snapshot.read(adapter, branch)
  |> result.map(fn(snapshot) { dependency_snapshot.dependencies(snapshot, ref) })
  |> result.unwrap([])
}

pub fn exclusive_closure(
  adapter: storage.StorageAdapter,
  root: DefinitionRef,
) -> List(DefinitionRef) {
  exclusive_closure_on_branch(adapter, default_branch, root)
}

pub fn exclusive_closure_on_branch(
  adapter: storage.StorageAdapter,
  branch: String,
  root: DefinitionRef,
) -> List(DefinitionRef) {
  dependency_snapshot.read(adapter, branch)
  |> result.map(fn(snapshot) {
    dependency_snapshot.exclusive_closure(snapshot, root)
  })
  |> result.unwrap([])
}

pub fn names_for(
  adapter: storage.StorageAdapter,
  ref: DefinitionRef,
) -> List(String) {
  names_for_on_branch(adapter, default_branch, ref)
}

pub fn names_for_on_branch(
  adapter: storage.StorageAdapter,
  branch: String,
  ref: DefinitionRef,
) -> List(String) {
  dependency_snapshot.read(adapter, branch)
  |> result.map(fn(snapshot) { dependency_snapshot.names(snapshot, ref) })
  |> result.unwrap([])
}

pub fn hex(ref: DefinitionRef) -> String {
  let Ref(hash) = ref
  hash_to_debug_string(hash)
}
