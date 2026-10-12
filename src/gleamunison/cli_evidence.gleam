//// `gleamunison evidence <hash>` — list the integrity-checked attestations
//// for a subject hash. "Did you test it?" becomes a lookup, not a promise.

import gleam/int
import gleam/io
import gleam/list
import gleam/string
import gleamunison/evidence
import gleamunison/storage.{type StorageAdapter}
import simplifile

pub fn command(args: List(String)) -> Nil {
  case args {
    [hash] -> run(hash)
    _ -> io.println("usage: gleam run -- evidence <subject-hash>")
  }
}

fn run(hash: String) -> Nil {
  let _ = simplifile.create_directory_all(".gleamunison")
  case storage.dets(".gleamunison/store.dets") {
    Error(e) -> io.println("evidence: cannot open store: " <> string.inspect(e))
    Ok(adapter) -> io.println(report(adapter, hash))
  }
}

/// A plain-text attestation report for a subject hash. Tampered chunks are
/// excluded upstream by for_subject (integrity re-verified on read), so
/// everything rendered here is proof, not claims.
pub fn report(adapter: StorageAdapter, subject: String) -> String {
  let records = evidence.for_subject(adapter, subject)
  case records {
    [] -> "no evidence for " <> subject
    _ -> {
      let lines =
        list.map(records, fn(e) {
          evidence.kind_name(e.kind)
          <> "  "
          <> e.verdict
          <> "  "
          <> e.payload
          <> "  (ts "
          <> int.to_string(e.ts)
          <> ")"
        })
      let verified_line = case
        evidence.verified(adapter, subject, evidence.Test)
      {
        True -> "verified: test evidence with passing verdict exists"
        False -> "verified: no passing test attestation"
      }
      string.join(
        [
          "evidence for " <> subject <> ":",
          ..list.append(lines, [verified_line])
        ],
        "\n",
      )
    }
  }
}
