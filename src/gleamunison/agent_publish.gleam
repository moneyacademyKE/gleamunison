//// Controlled agent publication: source -> tests -> signed evidence -> CAS
//// and selected branch. No caller-supplied storage key or arbitrary CAS write.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleamunison/ast
import gleamunison/cli_test
import gleamunison/evidence
import gleamunison/mcp
import gleamunison/publication
import gleamunison/schema_printer
import gleamunison/source_loader
import gleamunison/storage.{type StorageAdapter}
import gleamunison/test_runner

pub type Published {
  Published(name: String, content_ref: String)
}

pub type Publication {
  Publication(branch: String, definitions: List(Published), admitted: Int)
}

type SignatureCheck {
  Single(String)
  Target(String, String)
}

pub fn publish_source(
  adapter: StorageAdapter,
  source: String,
  branch: String,
  untrusted: Bool,
  log_directory: String,
) -> Result(Publication, String) {
  publish(adapter, source, branch, untrusted, log_directory, None)
}

/// A target-selected request may admit helpers, but only the named target
/// supplies the signature contract. All subjects use the same admission path.
pub fn publish_target_with_signature(
  adapter: StorageAdapter,
  source: String,
  branch: String,
  untrusted: Bool,
  log_directory: String,
  target: Option(String),
  expected_signature: String,
) -> Result(Publication, String) {
  let check = case target {
    None -> Single(expected_signature)
    Some(name) -> Target(name, expected_signature)
  }
  publish(adapter, source, branch, untrusted, log_directory, Some(check))
}

fn publish(
  adapter: StorageAdapter,
  source: String,
  branch: String,
  untrusted: Bool,
  log_directory: String,
  expected_signature: Option(SignatureCheck),
) -> Result(Publication, String) {
  case untrusted {
    True -> Error("agent_publish_refused: untrusted profile cannot write")
    False -> {
      use loaded <- result.try(source_loader.load(source))
      let names =
        publication.term_names(loaded.names, loaded.definitions)
        |> list.filter(fn(name) { !string.starts_with(name, "test_") })
      case names {
        [] -> Error("publish: no non-test term definitions supplied")
        _ -> {
          use subjects <- result.try(publication.subjects(
            names,
            loaded.definitions,
            loaded.cache,
          ))
          use _ <- result.try(check_signature(subjects, expected_signature))
          use _ <- result.try(test_and_attest(adapter, loaded))
          use _ <- result.try(publication.admit(
            adapter,
            log_directory,
            branch,
            subjects,
          ))
          Ok(Publication(
            branch:,
            definitions: list.map(subjects, fn(subject) {
              Published(subject.name, subject.content_ref)
            }),
            admitted: list.length(subjects),
          ))
        }
      }
    }
  }
}

fn check_signature(
  subjects: List(publication.Subject),
  expected: Option(SignatureCheck),
) -> Result(Nil, String) {
  case expected {
    None -> Ok(Nil)
    Some(Single(wanted)) ->
      case subjects {
        [subject] -> check_subject_signature(subject, wanted)
        _ ->
          Error(
            "publish: signature-constrained generation requires one target term",
          )
      }
    Some(Target(name, wanted)) -> {
      use subject <- result.try(
        list.find(subjects, fn(subject) { subject.name == name })
        |> result.replace_error(
          "publish: generation target not supplied: " <> name,
        ),
      )
      check_subject_signature(subject, wanted)
    }
  }
}

fn check_subject_signature(
  subject: publication.Subject,
  wanted: String,
) -> Result(Nil, String) {
  case subject.definition {
    ast.TermDef(typ:, ..) ->
      case schema_printer.to_schema(typ) == wanted {
        True -> Ok(Nil)
        False ->
          Error(
            "publish: signature mismatch for "
            <> subject.name
            <> ": inferred "
            <> schema_printer.to_schema(typ)
            <> ", requested "
            <> wanted,
          )
      }
    _ -> Error("publish: signature-constrained generation requires a term")
  }
}

fn test_and_attest(
  adapter: StorageAdapter,
  loaded: source_loader.LoadedSource,
) -> Result(Nil, String) {
  let results = test_runner.run_suite(loaded.definitions, loaded.cache)
  case list.is_empty(results) {
    True -> Ok(Nil)
    False -> attest_results(adapter, loaded, results)
  }
}

fn attest_results(
  adapter: StorageAdapter,
  loaded: source_loader.LoadedSource,
  results: List(test_runner.TestResult),
) -> Result(Nil, String) {
  case cli_test.has_failures(results) {
    True ->
      Error("publish: tests failed, missing, or had no passing assertions")
    False -> {
      use signer <- result.try(evidence.production_signer())
      let attachments =
        test_runner.attach_results_signed(
          adapter,
          results,
          loaded.definitions,
          loaded.cache,
          signer,
        )
      result.all(attachments)
      |> result.map_error(fn(error) {
        "cannot attach evidence: " <> string.inspect(error)
      })
      |> result.map(fn(_) { Nil })
    }
  }
}

pub fn json(publication: Publication) -> String {
  let definitions =
    list.map(publication.definitions, fn(item) {
      "{\"name\":"
      <> mcp.json_string(item.name)
      <> ",\"content_ref\":"
      <> mcp.json_string(item.content_ref)
      <> "}"
    })
  "{\"branch\":"
  <> mcp.json_string(publication.branch)
  <> ",\"admitted\":"
  <> int.to_string(publication.admitted)
  <> ",\"definitions\":["
  <> string.join(definitions, ",")
  <> "]}"
}
