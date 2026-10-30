//// Durable branch definitions and explicit source overlays share a read model.
//// Stored entries retain their AST and content identity; surface projections
//// are for elaboration only and are never presented as the original source.

import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleamunison/ast
import gleamunison/codebase
import gleamunison/elab_types.{type SurfaceDef, SRef, SurfaceTermDef}
import gleamunison/identity.{type DefinitionRef}
import gleamunison/loader
import gleamunison/lower.{type_ref_to_type}
import gleamunison/name_snapshot
import gleamunison/namespace
import gleamunison/repl_eval
import gleamunison/run_closure
import gleamunison/run_error
import gleamunison/storage.{type StorageAdapter}
import gleamunison/types.{type TypeCache, CTAbility, CTTerm, CTType, TypeCache}

pub type Origin {
  Bootstrap
  Scratch
  Branch(String)
}

pub type Entry {
  Source(name: String, definition: SurfaceDef, origin: Origin)
  Stored(
    name: String,
    ref: DefinitionRef,
    definition: ast.Definition,
    branch: String,
  )
}

pub type Selection {
  Selection(
    adapter: StorageAdapter,
    branch: String,
    names: name_snapshot.Bindings,
  )
}

pub fn name(entry: Entry) -> String {
  case entry {
    Source(name:, ..) | Stored(name:, ..) -> name
  }
}

pub fn origin(entry: Entry) -> Origin {
  case entry {
    Source(origin:, ..) -> origin
    Stored(branch:, ..) -> Branch(branch)
  }
}

pub fn stored_ref(entry: Entry) -> Option(DefinitionRef) {
  case entry {
    Stored(ref:, ..) -> Some(ref)
    Source(..) -> None
  }
}

pub fn projection(entry: Entry) -> Result(#(String, SurfaceDef), Nil) {
  case entry {
    Source(name:, definition:, ..) -> Ok(#(name, definition))
    Stored(name:, ref:, definition: ast.TermDef(..), ..) ->
      Ok(#(name, SurfaceTermDef(SRef(ref))))
    Stored(..) -> Error(Nil)
  }
}

pub fn definitions(entries: List(Entry)) -> List(#(String, SurfaceDef)) {
  list.filter_map(entries, projection)
}

pub fn cache(entries: List(Entry), baseline: TypeCache) -> TypeCache {
  list.fold(entries, baseline, fn(acc, entry) {
    case entry {
      Source(..) -> acc
      Stored(name:, ref:, definition:, ..) -> {
        let computed = case definition {
          ast.TermDef(typ:, ..) -> CTTerm(typ)
          ast.TypeDef(_) -> CTType
          ast.AbilityDecl(ast.AbilityDeclaration(operations:, ..)) ->
            CTAbility(
              list.map(operations, fn(operation) {
                types.OperationType(
                  name: None,
                  inputs: list.map(operation.inputs, type_ref_to_type),
                  output: type_ref_to_type(operation.output),
                )
              }),
            )
        }
        TypeCache(
          acc.entries
          |> dict.insert(ref, computed)
          |> dict.insert(repl_eval.ref_for_name(name), computed),
        )
      }
    }
  })
}

pub fn load(
  adapter: StorageAdapter,
  branch: String,
) -> Result(#(List(Entry), Selection), String) {
  // One immutable view per load: the bindings and the entries must come from
  // the same namespace. Reading twice doubled the branch I/O on the hot path
  // (mcp_session, generation_loop), and a write landing between the two reads
  // was the only way a bound name could fail to resolve below — a failure no
  // single consistent load can produce, so it is asserted, not mapped.
  use ns <- result.try(namespace.load_current_or_empty(adapter, branch))
  let names = name_snapshot.from_namespace(ns)
  let selection = Selection(adapter, branch, names)
  let cb = codebase.with_adapter(adapter)
  use entries <- result.try(
    list.try_map(namespace.names(ns), fn(name) {
      // `name` comes from this same ns, so the binding cannot miss: the
      // invariant name_snapshot.from_namespace already asserts.
      let assert Ok(ref) = namespace.get(ns, name)
      use definition <- result.try(
        codebase.get(cb, ref)
        |> result.map_error(fn(error) {
          run_error.describe(run_error.read_error(ref, error))
        }),
      )
      Ok(Stored(name, ref, definition, branch))
    }),
  )
  use _ <- result.try(
    list.try_fold(entries, loader.new_loader(), fn(ld, entry) {
      let assert Stored(name:, definition:, ..) = entry
      run_closure.resolve_definition(
        ld,
        cb,
        repl_eval.ref_for_name(name),
        definition,
        [],
        names,
      )
      |> result.map_error(run_error.describe)
    }),
  )
  Ok(#(entries, selection))
}
