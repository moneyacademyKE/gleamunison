//// The evidence turnstile as a reusable operation, independent of CLI I/O.

import gleam/list
import gleam/result
import gleam/string
import gleamunison/ast
import gleamunison/codebase
import gleamunison/effect_evidence
import gleamunison/elab_types
import gleamunison/identity.{Ref, hash_to_debug_string, parse_ref_hex}
import gleamunison/namespace
import gleamunison/storage.{type StorageAdapter}
import gleamunison/store_log
import gleamunison/test_runner
import gleamunison/trust
import gleamunison/turnstile
import gleamunison/types.{type TypeCache}

pub type Subject {
  Subject(name: String, content_ref: String, definition: ast.Definition)
}

pub fn subjects(
  names: List(String),
  definitions: List(#(String, elab_types.SurfaceDef)),
  cache: TypeCache,
) -> Result(List(Subject), String) {
  list.try_map(names, fn(name) {
    case test_runner.elaborated_def_for(name, definitions, cache) {
      Error(reason) -> Error("cannot elaborate " <> name <> ": " <> reason)
      Ok(definition) -> {
        let Ref(hash) = Ref(codebase.hash_of_definition(definition))
        Ok(Subject(name, hash_to_debug_string(hash), definition))
      }
    }
  })
}

pub fn admit(
  adapter: StorageAdapter,
  directory: String,
  branch: String,
  selected: List(Subject),
) -> Result(Nil, String) {
  let pairs =
    list.map(selected, fn(subject) {
      #(
        subject.name,
        subject.content_ref,
        effect_evidence.definition_is_effectful(subject.definition),
      )
    })
  use policy <- result.try(trust.production_policy())
  case turnstile.check_with_policy(adapter, pairs, policy) {
    Error(missing) ->
      Error(
        "publish: REFUSED — no evidence for: "
        <> string.join(missing, ", ")
        <> "; run tests or attest the named content hashes",
      )
    Ok(_) -> {
      use _ <- result.try(store_definitions(adapter, directory, selected))
      bind_names(adapter, branch, selected)
    }
  }
}

fn store_definitions(
  adapter: StorageAdapter,
  directory: String,
  selected: List(Subject),
) -> Result(Nil, String) {
  let cb = codebase.with_adapter(adapter)
  use _ <- result.try(
    list.try_fold(selected, cb, fn(cb, subject) {
      let ref = Ref(codebase.hash_of_definition(subject.definition))
      use _ <- result.try(
        codebase.insert(
          cb,
          ast.Unit(root: ref, defs: [#(ref, subject.definition)]),
        )
        |> result.map_error(fn(error) {
          "cannot store " <> subject.name <> ": " <> string.inspect(error)
        }),
      )
      store_log.record_content(directory, subject.content_ref, "term")
      |> result.map_error(fn(reason) {
        "cannot record " <> subject.name <> ": " <> reason
      })
      |> result.replace(cb)
    }),
  )
  Ok(Nil)
}

fn bind_names(
  adapter: StorageAdapter,
  branch: String,
  selected: List(Subject),
) -> Result(Nil, String) {
  use current <- result.try(
    namespace.load_current_or_empty(adapter, branch)
    |> result.map_error(fn(reason) { "cannot read branch: " <> reason }),
  )
  use next <- result.try(
    list.try_fold(selected, current, fn(ns, subject) {
      use ref <- result.try(
        parse_ref_hex(subject.content_ref)
        |> result.map_error(fn(reason) {
          "cannot bind " <> subject.name <> ": " <> reason
        }),
      )
      Ok(namespace.set(ns, subject.name, ref))
    }),
  )
  namespace.commit(adapter, branch, next)
  |> result.map_error(fn(reason) { "cannot commit namespace: " <> reason })
  |> result.map(fn(_) { Nil })
}

pub fn term_names(
  names: List(String),
  definitions: List(#(String, elab_types.SurfaceDef)),
) -> List(String) {
  list.filter(names, fn(name) {
    case list.key_find(definitions, name) {
      Ok(elab_types.SurfaceTermDef(_)) -> True
      _ -> False
    }
  })
}
