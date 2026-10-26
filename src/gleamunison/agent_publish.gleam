//// Controlled agent publication: source -> tests -> signed evidence -> CAS
//// and selected branch. No caller-supplied storage key or arbitrary CAS write.

import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleamunison/cli_test
import gleamunison/evidence
import gleamunison/mcp
import gleamunison/publication
import gleamunison/source_loader
import gleamunison/storage.{type StorageAdapter}
import gleamunison/test_runner

pub type Published {
  Published(name: String, content_ref: String)
}

pub type Publication {
  Publication(branch: String, definitions: List(Published), admitted: Int)
}

pub fn publish_source(
  adapter: StorageAdapter,
  source: String,
  branch: String,
  untrusted: Bool,
  log_directory: String,
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
