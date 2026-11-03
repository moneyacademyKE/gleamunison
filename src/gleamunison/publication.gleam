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

/// A named, content-addressed definition selected for publication.
pub type Subject {
  Subject(name: String, content_ref: String, definition: ast.Definition)
}

/// Why publication was refused.
///
/// `MissingEvidence` carries the refused subjects so a caller can render the
/// evidence turnstile's guidance; `Failed` carries an already-rendered reason
/// for policy, storage, or namespace failures.
pub type AdmitError {
  MissingEvidence(subjects: List(Subject))
  Failed(reason: String)
}

type Entry {
  Entry(
    name: String,
    content_ref: String,
    definition: ast.Definition,
    term: ast.Term,
  )
}

/// Render an admission refusal as the canonical CLI guidance.
pub fn describe_error(error: AdmitError) -> String {
  case error {
    MissingEvidence(missing) ->
      "publish: REFUSED — no evidence for: "
      <> string.join(list.map(missing, fn(s) { s.name }), ", ")
      <> "; run tests or attest the named content hashes"
    Failed(reason) -> reason
  }
}

/// Elaborate selected definitions exactly once, keeping the term needed for
/// transitive effect classification alongside the stored definition.
fn elaborate(
  names: List(String),
  definitions: List(#(String, elab_types.SurfaceDef)),
  cache: TypeCache,
) -> Result(List(Entry), String) {
  list.try_map(names, fn(name) {
    case test_runner.elaborated_def_for(name, definitions, cache) {
      Error(reason) -> Error("cannot elaborate " <> name <> ": " <> reason)
      Ok(definition) ->
        case definition {
          ast.TermDef(term, _) -> {
            let Ref(hash) = Ref(codebase.hash_of_definition(definition))
            Ok(Entry(name, hash_to_debug_string(hash), definition, term))
          }
          _ -> Error(name <> " is not a term definition")
        }
    }
  })
}

/// Elaborate definitions into publishable subjects.
pub fn subjects(
  names: List(String),
  definitions: List(#(String, elab_types.SurfaceDef)),
  cache: TypeCache,
) -> Result(List(Subject), String) {
  use entries <- result.try(elaborate(names, definitions, cache))
  Ok(
    list.map(entries, fn(entry) {
      Subject(entry.name, entry.content_ref, entry.definition)
    }),
  )
}

/// Elaborate definitions into evidence triples: name, content ref, effectful.
///
/// Effectfulness is computed across the whole batch, so a pure caller of an
/// effectful batch member still requires evidence.
pub fn hash_defs(
  names: List(String),
  definitions: List(#(String, elab_types.SurfaceDef)),
  cache: TypeCache,
) -> Result(List(#(String, String, Bool)), String) {
  use entries <- result.try(elaborate(names, definitions, cache))
  let effectful = effect_evidence.batch_effectful(batch_entries(entries))
  Ok(
    list.map(entries, fn(entry) {
      #(entry.name, entry.content_ref, list.contains(effectful, entry.name))
    }),
  )
}

/// Admit selected subjects through the evidence turnstile, store their content,
/// and bind their names on the target branch.
pub fn admit(
  adapter: StorageAdapter,
  directory: String,
  branch: String,
  selected: List(Subject),
) -> Result(Nil, AdmitError) {
  let effectful =
    effect_evidence.batch_effectful(
      list.filter_map(selected, fn(subject) {
        case subject.definition {
          ast.TermDef(term, _) ->
            Ok(effect_evidence.BatchEntry(
              subject.name,
              subject.content_ref,
              term,
            ))
          _ -> Error(Nil)
        }
      }),
    )
  let pairs =
    list.map(selected, fn(subject) {
      #(
        subject.name,
        subject.content_ref,
        list.contains(effectful, subject.name),
      )
    })

  use policy <- result.try(
    trust.production_policy()
    |> result.map_error(fn(reason) { Failed(reason) }),
  )

  case turnstile.check_with_policy(adapter, pairs, policy) {
    Error(missing) ->
      Error(MissingEvidence(missing_subjects(missing, selected)))
    Ok(_) -> {
      use _ <- result.try(
        store_definitions(adapter, directory, selected)
        |> result.map_error(Failed),
      )
      bind_names(adapter, branch, selected)
      |> result.map_error(Failed)
    }
  }
}

fn batch_entries(entries: List(Entry)) -> List(effect_evidence.BatchEntry) {
  list.map(entries, fn(entry) {
    effect_evidence.BatchEntry(entry.name, entry.content_ref, entry.term)
  })
}

fn missing_subjects(
  missing: List(String),
  selected: List(Subject),
) -> List(Subject) {
  list.filter_map(missing, fn(name) {
    case list.find(selected, fn(subject) { subject.name == name }) {
      Ok(subject) -> Ok(subject)
      Error(_) -> Error(Nil)
    }
  })
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
          "cannot store "
          <> subject.name
          <> ": "
          <> codebase.describe_insert_error(error)
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

/// Keep only names that bind surface term definitions.
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
