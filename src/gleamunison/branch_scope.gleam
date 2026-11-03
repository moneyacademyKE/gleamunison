//// Read-only questions that span branches: which branches this store knows, and
//// which of them bind a given piece of content.
////
//// The name layer answers branch-local questions (namespace.gleam owns the
//// pointers and the commit); this module is the read model over all of them. It
//// exists because content is shared and names are not: a retraction scoped to
//// one namespace cannot see that another branch still resolves to the ref, so it
//// would delete bytes a different branch still loads.
////
//// Branch pointers are the registry. Each is a chunk keyed by its branch name
//// whose bytes carry that name back, so a scan of the store recovers the set
//// without a second index to keep in sync.

import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleamunison/identity.{type DefinitionRef}
import gleamunison/namespace
import gleamunison/storage

/// Every branch this store knows about, sorted.
pub fn branches(
  adapter: storage.StorageAdapter,
) -> Result(List(String), String) {
  use refs <- result.try(
    adapter.list_refs()
    |> result.map_error(storage.describe_error),
  )
  use found <- result.try(
    list.try_fold(refs, [], fn(acc, ref) {
      use bytes <- result.try(
        adapter.lookup(ref)
        |> result.map_error(storage.describe_error),
      )
      case bytes {
        // A vanished ref cannot prove that no branch binds the content.
        option.None -> Error("branch pointer missing")
        option.Some(b) ->
          // The pointer bytes are read, not assumed from the key: a chunk under a
          // branch-shaped key that does not carry that branch is not a branch.
          case namespace.branch_name_of(ref, b) {
            option.Some(branch) -> Ok([branch, ..acc])
            option.None -> Ok(acc)
          }
      }
    }),
  )
  Ok(list.sort(found, string.compare))
}

/// Every (branch, name) pair that binds this content, across all branches.
pub fn branches_binding(
  adapter: storage.StorageAdapter,
  ref: DefinitionRef,
) -> Result(List(#(String, String)), String) {
  use known <- result.try(branches(adapter))
  use found <- result.try(
    list.try_fold(known, [], fn(acc, branch) {
      use ns <- result.try(namespace.load_current_or_empty(adapter, branch))
      let hits =
        ns
        |> namespace.names_for_ref(ref)
        |> list.map(fn(name) { #(branch, name) })
      Ok(list.append(acc, hits))
    }),
  )
  Ok(found)
}
