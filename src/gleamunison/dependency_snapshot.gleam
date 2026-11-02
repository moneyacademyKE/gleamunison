//// One verified, branch-local view for a complete retraction decision.
//// No persistent index or invalidation policy: read once, then query pure data.

import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/set
import gleamunison/definition_codec
import gleamunison/definition_refs
import gleamunison/identity.{type DefinitionRef}
import gleamunison/name_snapshot
import gleamunison/namespace
import gleamunison/storage

pub type ScanError {
  StoreFailure(storage.StorageError)
  NamespaceFailure(String)
  CorruptDefinition(DefinitionRef)
}

pub opaque type Snapshot {
  Snapshot(
    ns: namespace.Namespace,
    uses: Dict(DefinitionRef, List(DefinitionRef)),
    callers: Dict(DefinitionRef, List(DefinitionRef)),
  )
}

pub fn read(
  adapter: storage.StorageAdapter,
  branch: String,
) -> Result(Snapshot, ScanError) {
  use ns <- result.try(
    namespace.load_current_or_empty(adapter, branch)
    |> result.map_error(NamespaceFailure),
  )
  let bindings = name_snapshot.from_namespace(ns)
  use refs <- result.try(adapter.list_refs() |> result.map_error(StoreFailure))
  use uses <- result.try(
    list.try_fold(refs, dict.new(), fn(acc, ref) {
      use bytes <- result.try(
        adapter.lookup(ref) |> result.map_error(StoreFailure),
      )
      case bytes {
        None -> Error(CorruptDefinition(ref))
        Some(bytes) -> {
          use _ <- result.try(case namespace.is_branch_pointer(ref, bytes) {
            True -> Ok(Nil)
            False ->
              storage.verify_content(ref, bytes)
              |> result.replace_error(CorruptDefinition(ref))
          })
          case definition_codec.decode(bytes) {
            Ok(definition) -> {
              let dependencies =
                definition_refs.refs_of_definition(definition)
                |> list.map(fn(dep) {
                  dict.get(bindings, dep) |> result.unwrap(dep)
                })
                |> list.unique
              Ok(dict.insert(acc, ref, dependencies))
            }
            Error(_) ->
              case bytes {
                <<"GUDEF":utf8, _:bits>> -> Error(CorruptDefinition(ref))
                _ -> Ok(acc)
              }
          }
        }
      }
    }),
  )
  let callers =
    dict.fold(uses, dict.new(), fn(index, ref, deps) {
      list.fold(deps, index, fn(index, dep) {
        dict.insert(index, dep, [ref, ..result.unwrap(dict.get(index, dep), [])])
      })
    })
  Ok(Snapshot(ns, uses, callers))
}

pub fn current_namespace(snapshot: Snapshot) -> namespace.Namespace {
  snapshot.ns
}

pub fn dependents(
  snapshot: Snapshot,
  ref: DefinitionRef,
) -> List(DefinitionRef) {
  dict.get(snapshot.callers, ref)
  |> result.unwrap([])
  |> list.filter(fn(caller) { caller != ref })
}

pub fn names(snapshot: Snapshot, ref: DefinitionRef) -> List(String) {
  namespace.names_for_ref(snapshot.ns, ref)
}

pub fn dependencies(
  snapshot: Snapshot,
  ref: DefinitionRef,
) -> List(DefinitionRef) {
  dict.get(snapshot.uses, ref)
  |> result.unwrap([])
  |> list.filter(fn(dep) { dict.has_key(snapshot.uses, dep) })
}

pub fn exclusive_closure(
  snapshot: Snapshot,
  root: DefinitionRef,
) -> List(DefinitionRef) {
  expand(snapshot, [root], set.from_list([root]))
}

fn expand(
  snapshot: Snapshot,
  selected: List(DefinitionRef),
  members,
) -> List(DefinitionRef) {
  let additions =
    selected
    |> list.flat_map(fn(ref) { dependencies(snapshot, ref) })
    |> list.unique
    |> list.filter(fn(dep) {
      !set.contains(members, dep)
      && list.all(dependents(snapshot, dep), fn(caller) {
        set.contains(members, caller)
      })
    })
  case additions {
    [] -> selected
    _ ->
      expand(
        snapshot,
        list.append(selected, additions),
        set.union(members, set.from_list(additions)),
      )
  }
}
