//// Run in-language tests and persist evidence before reporting success.

import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleamunison/evidence
import gleamunison/storage.{type StorageAdapter}
import gleamunison/test_runner.{type TestResult}
import gleamunison/verify
import simplifile

@external(erlang, "gleamunison_ffi", "halt_failure")
fn halt_failure() -> Nil

/// Attachments produced by a run: subject hash + human payload, in order.
pub type Attachments =
  List(#(String, String))

/// No tests or no assertions is not a successful test run.
pub fn has_failures(results: List(TestResult)) -> Bool {
  list.is_empty(results)
  || list.any(results, fn(r) {
    r.passed + r.failed == 0 || r.failed > 0 || r.error != option.None
  })
}

pub fn command(args: List(String)) -> Nil {
  case args {
    [path] -> run(path)
    _ -> fail("usage: gleam run -- test <file.lisp>")
  }
}

fn fail(message: String) -> Nil {
  io.println(message)
  halt_failure()
}

fn run(path: String) -> Nil {
  case evidence.production_signer() {
    Error(reason) -> fail("test: " <> reason)
    Ok(signer) -> run_with_signer(path, signer)
  }
}

fn run_with_signer(path: String, signer: evidence.Signer) -> Nil {
  case simplifile.create_directory_all(".gleamunison") {
    Error(e) -> fail("test: cannot create store: " <> string.inspect(e))
    Ok(_) ->
      case storage.dets(".gleamunison/store.dets") {
        Error(e) -> fail("test: cannot open store: " <> string.inspect(e))
        Ok(adapter) -> {
          let outcome = run_file_with_signer(path, adapter, signer)
          // This command owns the adapter. Closing flushes buffered DETS
          // writes before any success message or nonzero process exit.
          case adapter.close() {
            Error(e) -> fail("test: cannot close store: " <> string.inspect(e))
            Ok(_) ->
              case outcome {
                Error(err) -> fail("test: " <> err)
                Ok(#(results, attachments)) -> report(results, attachments)
              }
          }
        }
      }
  }
}

fn report(results: List(TestResult), attachments: Attachments) -> Nil {
  list.each(results, fn(r) { io.println(format_result(r)) })
  let failed = list.count(results, fn(r) { has_failures([r]) })
  io.println(
    int.to_string(list.length(results))
    <> " tests, "
    <> int.to_string(failed)
    <> " failed, "
    <> int.to_string(list.length(attachments))
    <> " evidence records attached",
  )
  list.each(attachments, fn(a) {
    io.println("evidence: " <> a.0 <> "  " <> a.1)
  })
  case results {
    [] -> fail("test: no test_ definitions found")
    _ ->
      case has_failures(results) {
        True -> halt_failure()
        False -> Nil
      }
  }
}

fn format_result(r: TestResult) -> String {
  let status = case r.error, r.failed {
    option.Some(e), _ -> "error: " <> e
    option.None, 0 -> "pass"
    option.None, _ -> "fail"
  }
  r.name
  <> "  "
  <> status
  <> "  ("
  <> int.to_string(r.passed + r.failed)
  <> " assertions)"
}

/// The caller owns the supplied adapter. Failed insertions are errors,
/// not missing attachments silently discarded from a successful report.
pub fn run_file(
  path: String,
  adapter: StorageAdapter,
) -> Result(#(List(TestResult), Attachments), String) {
  use #(cache, defs) <- result.try(verify.load_defs_file(path))
  let results = test_runner.run_suite(defs, cache)
  let attached = test_runner.attach_results(adapter, results, defs, cache)
  use records <- result.try(
    result.all(attached)
    |> result.map_error(fn(e) {
      "cannot attach evidence: " <> string.inspect(e)
    }),
  )
  Ok(#(
    results,
    list.map(records, fn(a) {
      let #(subject_hex, _evidence_ref, payload) = a
      #(subject_hex, payload)
    }),
  ))
}

pub fn run_file_with_signer(
  path: String,
  adapter: StorageAdapter,
  signer: evidence.Signer,
) -> Result(#(List(TestResult), Attachments), String) {
  use #(cache, defs) <- result.try(verify.load_defs_file(path))
  let results = test_runner.run_suite(defs, cache)
  let attached =
    test_runner.attach_results_signed(adapter, results, defs, cache, signer)
  use records <- result.try(
    result.all(attached)
    |> result.map_error(fn(e) {
      "cannot attach evidence: " <> string.inspect(e)
    }),
  )
  Ok(#(
    results,
    list.map(records, fn(a) {
      let #(subject_hex, _evidence_ref, payload) = a
      #(subject_hex, payload)
    }),
  ))
}
