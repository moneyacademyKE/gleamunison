//// `gleamunison test <file.lisp>` — run every `test_` definition under a
//// recording Test handler and attest the results into the codebase store.
//// The loop this closes: test outcomes stop being chat and become evidence
//// attached to content hashes — "did you test it?" becomes a lookup.

import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleamunison/storage.{type StorageAdapter}
import gleamunison/test_runner.{type TestResult}
import gleamunison/verify
import simplifile

/// Attachments produced by a run: subject hash + human payload, in order.
pub type Attachments =
  List(#(String, String))

pub fn command(args: List(String)) -> Nil {
  case args {
    [path] -> run(path)
    _ -> io.println("usage: gleam run -- test <file.lisp>")
  }
}

fn run(path: String) -> Nil {
  // The project store: where evidence lives between runs. Create the
  // directory: dets opens files, it does not invent their parents.
  let _ = simplifile.create_directory_all(".gleamunison")
  case storage.dets(".gleamunison/store.dets") {
    Error(e) -> io.println("test: cannot open store: " <> string.inspect(e))
    Ok(adapter) ->
      case run_file(path, adapter) {
        Error(err) -> io.println("test: " <> err)
        Ok(#(results, attachments)) -> {
          list.each(results, fn(r) { io.println(format_result(r)) })
          let failed =
            list.count(results, fn(r) { r.failed > 0 || r.error != option.None })
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
        }
      }
  }
}

fn format_result(r: TestResult) -> String {
  let status = case r.error, r.failed {
    option.Some(e), _ -> "error: " <> e
    option.None, 0 -> "pass"
    option.None, _ -> "fail"
  }
  r.name <> "  " <> status <> "  (" <> int.to_string(r.passed) <> " assertions)"
}

/// Load a suite file, run it, attach evidence per subject hash.
/// Returns results plus the (subject_hex, payload) pairs attested.
pub fn run_file(
  path: String,
  adapter: StorageAdapter,
) -> Result(#(List(TestResult), Attachments), String) {
  use #(cache, defs) <- result.try(verify.load_defs_file(path))
  let results = test_runner.run_suite(defs, cache)
  let attached = test_runner.attach_results(adapter, results, defs, cache)
  let ok_attachments =
    list.filter_map(attached, fn(a) {
      case a {
        Ok(#(subject_hex, _evidence_ref, payload)) ->
          Ok(#(subject_hex, payload))
        Error(_) -> Error(Nil)
      }
    })
  Ok(#(results, ok_attachments))
}
