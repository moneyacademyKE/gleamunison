//// Who depends on a stored definition.
////
//// One pass over the store, decoding each payload as a definition and
//// collecting the refs it names. This is O(store size) per query and there is
//// no index: for a local store that is microseconds, and an index would be a
//// second thing to keep correct. Callers that retract content (unpublish,
//// purge) ask this first, so nothing disappears out from under a live
//// definition.
////
//// Name refs are the subtlety: an elaborated term references its dependencies
//// by sha256(name), not by content hash, so a scan that only matches content
//// refs would report no dependents for a definition that is very much in use.
//// Both spellings are matched.

import gleam/list
import gleamunison/codebase
import gleamunison/definition_refs
import gleamunison/identity.{type DefinitionRef, Ref, hash_to_debug_string}
import gleamunison/namespace
import gleamunison/repl_eval
import gleamunison/storage

const default_branch = "main"

/// Every stored definition that references `target`, either by its content ref
/// or by a name ref that currently binds to it.
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
  let name_refs = name_refs_for(adapter, branch, target)
  let cb = codebase.with_adapter(adapter)
  case adapter.list_refs() {
    Error(_) -> []
    Ok(refs) ->
      list.filter_map(refs, fn(ref) {
        case ref == target {
          True -> Error(Nil)
          False -> {
            case codebase.get(cb, ref) {
              Error(_) -> Error(Nil)
              Ok(definition) -> {
                let refs_used = definition_refs.refs_of_definition(definition)
                let names_used =
                  list.any(name_refs, fn(name_ref) {
                    list.contains(refs_used, name_ref)
                  })
                case list.contains(refs_used, target) || names_used {
                  True -> Ok(ref)
                  False -> Error(Nil)
                }
              }
            }
          }
        }
      })
  }
}

/// The name refs that currently resolve to `target` on this branch.
fn name_refs_for(
  adapter: storage.StorageAdapter,
  branch: String,
  target: DefinitionRef,
) -> List(DefinitionRef) {
  case namespace.load_current(adapter, branch) {
    Error(_) -> []
    Ok(ns) ->
      list.filter_map(namespace.names(ns), fn(name) {
        case namespace.get(ns, name) {
          Ok(content) if content == target -> Ok(repl_eval.ref_for_name(name))
          _ -> Error(Nil)
        }
      })
  }
}

/// Names (published bindings) that currently resolve to `target`, other than
/// the one being retracted.
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
  case namespace.load_current(adapter, branch) {
    Error(_) -> []
    Ok(ns) ->
      list.filter(namespace.names(ns), fn(name) {
        name != retracting && namespace.get(ns, name) == Ok(target)
      })
  }
}

pub fn hex(ref: DefinitionRef) -> String {
  let Ref(hash) = ref
  hash_to_debug_string(hash)
}

/// The stored content refs a definition depends on, with name refs resolved
/// through the namespace. Builtins and jets have no store entry, so they are
/// absent here: there is nothing to remove for them.
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
  let cb = codebase.with_adapter(adapter)
  case codebase.get(cb, ref) {
    Error(_) -> []
    Ok(definition) ->
      definition_refs.refs_of_definition(definition)
      |> list.filter_map(fn(dependency) {
        case codebase.get(cb, dependency) {
          Ok(_) -> Ok(dependency)
          Error(_) ->
            // A name ref: the bytes live under the content ref it binds.
            case resolve_name(adapter, branch, dependency) {
              Ok(content_ref) -> Ok(content_ref)
              Error(_) -> Error(Nil)
            }
        }
      })
      |> list.unique
  }
}

fn resolve_name(
  adapter: storage.StorageAdapter,
  branch: String,
  name_ref: DefinitionRef,
) -> Result(DefinitionRef, Nil) {
  case namespace.load_current(adapter, branch) {
    Error(_) -> Error(Nil)
    Ok(ns) ->
      list.find_map(namespace.names(ns), fn(name) {
        case repl_eval.ref_for_name(name) == name_ref {
          True ->
            case namespace.get(ns, name) {
              Ok(content_ref) -> Ok(content_ref)
              Error(_) -> Error(Nil)
            }
          False -> Error(Nil)
        }
      })
  }
}

/// The ref plus every stored dependency that nothing outside the set uses:
/// removing a definition removes what only it kept alive, and nothing else.
/// Iterated to a fixpoint because a dependency becomes exclusive once its
/// other dependents are themselves in the set.
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
  let roots = [root]
  expand(adapter, branch, roots, 0)
}

const max_rounds = 64

fn expand(
  adapter: storage.StorageAdapter,
  branch: String,
  set: List(DefinitionRef),
  round: Int,
) -> List(DefinitionRef) {
  case round >= max_rounds {
    True -> set
    False -> {
      let candidates =
        list.flat_map(set, fn(ref) {
          stored_dependencies_on_branch(adapter, branch, ref)
        })
        |> list.filter(fn(dep) { !list.contains(set, dep) })
        |> list.unique
      let additions =
        list.filter(candidates, fn(dep) {
          dependents_on_branch(adapter, branch, dep)
          |> list.all(fn(dependent) { list.contains(set, dependent) })
        })
      case additions {
        [] -> set
        _ -> expand(adapter, branch, list.append(set, additions), round + 1)
      }
    }
  }
}

/// Every name bound to `ref` on this branch.
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
  case namespace.load_current(adapter, branch) {
    Error(_) -> []
    Ok(ns) ->
      list.filter(namespace.names(ns), fn(name) {
        namespace.get(ns, name) == Ok(ref)
      })
  }
}
