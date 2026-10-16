//// `gleamunison evidence <hash>` — list the integrity-checked attestations
//// for a subject hash. "Did you test it?" becomes a lookup, not a promise.
////
//// `gleamunison evidence attest <hash> io <note...>` — human attestation
//// for effectful defs. Only `io` is attestable by hand: test/review/
//// property evidence must come from the tools that ran them.

import gleam/int
import gleam/io
import gleam/list
import gleam/string
import gleamunison/datetime
import gleamunison/evidence
import gleamunison/storage.{type StorageAdapter}
import simplifile

pub fn command(args: List(String)) -> Nil {
  case args {
    [hash] -> run(hash)
    ["attest", hash, "io", ..note] -> attest(hash, string.join(note, " "))
    _ ->
      io.println(
        "usage: gleam run -- evidence <subject-hash>\n"
        <> "       gleam run -- evidence attest <subject-hash> io <note...>",
      )
  }
}

fn attest(hash: String, note: String) -> Nil {
  case note {
    "" ->
      io.println("evidence attest: a note is required — say what you observed")
    _ -> {
      let _ = simplifile.create_directory_all(".gleamunison")
      case storage.dets(".gleamunison/store.dets") {
        Error(e) ->
          io.println("evidence: cannot open store: " <> string.inspect(e))
        Ok(adapter) ->
          case
            evidence.attach(
              adapter,
              subject: hash,
              kind: evidence.Io,
              verdict: "approved",
              payload: note,
              ts: datetime.to_unix(datetime.now()),
            )
          {
            Ok(#(_, hex)) ->
              io.println(
                "attested io on " <> hash <> " (evidence " <> hex <> ")",
              )
            Error(_) -> io.println("evidence attest: store insert failed")
          }
      }
    }
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
      let io_line = case evidence.verified(adapter, subject, evidence.Io) {
        True -> "io: human-approved attestation exists"
        False -> "io: no io attestation"
      }
      string.join(
        [
          "evidence for " <> subject <> ":",
          ..list.append(lines, [verified_line, io_line])
        ],
        "\n",
      )
    }
  }
}
