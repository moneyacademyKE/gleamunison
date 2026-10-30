//// Walk a ref's dependency closure and load it, dependencies first.
////
//// A compiled module calls its dependencies by module name at run time, so
//// loading one definition honestly means loading everything it points at
//// before it. This module is that walk and the decision of what counts as
//// already present in the runtime; it does not execute anything and does not
//// know about the evidence gate.

import gleam/dict
import gleam/list
import gleam/result
import gleamunison/ast
import gleamunison/bootstrap_types
import gleamunison/bootstraps
import gleamunison/codebase
import gleamunison/definition_refs
import gleamunison/identity.{type DefinitionRef}
import gleamunison/loader
import gleamunison/name_snapshot
import gleamunison/run_error.{
  type RunError, Cycle, LoadFailed, Missing, describe_load, read_error,
}

pub fn resolve(
  ld: loader.Loader,
  cb: codebase.Codebase,
  ref: DefinitionRef,
  visiting: List(DefinitionRef),
  names: name_snapshot.Bindings,
) -> Result(loader.Loader, RunError) {
  case loader.is_loaded(ld, ref) {
    True -> Ok(ld)
    False ->
      case codebase.get(cb, ref) {
        Ok(definition) ->
          resolve_definition(ld, cb, ref, definition, visiting, names)
        Error(codebase.NotFound(_)) ->
          // Resolve the selected branch before consulting the VM module table.
          case dict.get(names, ref) {
            Ok(content_ref) -> {
              use definition <- result.try(
                codebase.get(cb, content_ref)
                |> result.map_error(fn(error) { read_error(content_ref, error) }),
              )
              resolve_definition(ld, cb, ref, definition, visiting, names)
            }
            Error(_) -> resolve_runtime_ref(ld, ref)
          }
        Error(other) -> Error(read_error(ref, other))
      }
  }
}

pub fn resolve_definition(
  ld: loader.Loader,
  cb: codebase.Codebase,
  ref: DefinitionRef,
  definition: ast.Definition,
  visiting: List(DefinitionRef),
  names: name_snapshot.Bindings,
) -> Result(loader.Loader, RunError) {
  case list.contains(visiting, ref) {
    // Content addressing makes this unreachable by construction: a definition
    // cannot hash its own hash. Reaching it means the store admitted content
    // that does not match its key.
    True -> Error(Cycle(ref))
    False -> {
      let visiting = [ref, ..visiting]
      use ld <- result.try(
        list.try_fold(
          definition_refs.refs_of_definition(definition),
          ld,
          fn(ld, dependency) { resolve(ld, cb, dependency, visiting, names) },
        ),
      )
      loader.ensure_loaded(ld, ref, definition)
      |> result.map_error(fn(pair) { LoadFailed(ref, describe_load(pair.1)) })
    }
  }
}

/// Whether a ref names something the baseline environment already provides.
///
/// The elaborator references a dependency as `ref_for_name(name)` — sha256 of
/// the name — for every bootstrap entry, terms included. The synthetic genesis
/// ref (`<<1:256>>`, ...) is an internal handle for the *definition* of a
/// builtin; no elaborated term ever points at it. Matching only the genesis ref
/// therefore declared every builtin missing, and `run` on a stored definition
/// could not resolve `+`. Both shapes name the same builtin, so both count.
fn is_bootstrap_ref(ref: DefinitionRef) -> Bool {
  list.any(bootstraps.get_init_defs_data(), fn(definition) {
    case definition {
      bootstraps.BAbility(name, _) -> identity.name_ref(name) == ref
      bootstraps.BTerm(name, known_ref, _) ->
        known_ref == ref || identity.name_ref(name) == ref
    }
  })
}

fn resolve_runtime_ref(
  ld: loader.Loader,
  ref: DefinitionRef,
) -> Result(loader.Loader, RunError) {
  case
    bootstrap_types.is_type_ref(ref)
    || { is_bootstrap_ref(ref) && loader.module_available(ref) }
  {
    True -> Ok(ld)
    False -> Error(Missing(ref))
  }
}
