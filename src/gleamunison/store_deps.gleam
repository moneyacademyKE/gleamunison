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

const branch = "main"

/// Every stored definition that references `target`, either by its content ref
/// or by a name ref that currently binds to it.
pub fn dependents(
  adapter: storage.StorageAdapter,
  target: DefinitionRef,
) -> List(DefinitionRef) {
  let name_refs = name_refs_for(adapter, target)
  let cb = codebase.with_adapter(adapter)
  case adapter.list_refs() {
    Error(_) -> []
    Ok(refs) ->
      list.filter_map(refs, fn(ref) {
        case ref == target {
          True -> Error(Nil)
          False -> {
            case codebase.get(cb, ref) {
              // Payloads that are not definitions (namespace chunks, head
              // pointers, evidence records) are skipped, not errors.
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
