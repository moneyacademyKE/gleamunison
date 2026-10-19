//// `gleamunison evidence <hash>` — list the integrity-checked attestations
//// for a subject hash. "Did you test it?" becomes a lookup, not a promise.
////
//// `gleamunison evidence attest <hash> io <note...>` — human attestation
//// for effectful defs. Only `io` is attestable by hand: test/review/
//// property evidence must come from the tools that ran them.

import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleamunison/cli_result
import gleamunison/cli_store
import gleamunison/datetime
import gleamunison/evidence
import gleamunison/storage.{type StorageAdapter}

pub fn command(args: List(String)) -> Result(Nil, String) {
  case args {
    [hash] -> run(hash)
    ["attest", hash, "io", ..note] -> attest(hash, string.join(note, " "))
    _ ->
      Error(
        "usage: gleam run -- evidence <content-hash>\n"
        <> "       gleam run -- evidence attest <content-hash> io <note...>\n"
        <> "\n"
        <> "The hash is the content hash (the `hash:` line from `view`),\n"
        <> "not the name ref (the `ref:` line). Evidence attaches to the\n"
        <> "elaborated term, so a name ref will be refused by publish.",
      )
  }
}

fn attest(hash: String, note: String) -> Result(Nil, String) {
  case note {
    "" -> Error("evidence attest: a note is required — say what you observed")
    _ -> {
      use signer <- result.try(evidence.production_signer())
      use output <- result.try(
        cli_store.with_dets(".gleamunison/store.dets", fn(adapter) {
          evidence.attach_signed(
            adapter,
            signer,
            subject: hash,
            kind: evidence.Io,
            verdict: "approved",
            payload: note,
            ts: datetime.to_unix(datetime.now()),
          )
          |> result.map(fn(pair) {
            "attested io on " <> hash <> " (evidence " <> pair.1 <> ")"
          })
          |> result.map_error(fn(_) { "evidence attest: store insert failed" })
        }),
      )
      cli_result.success(output)
    }
  }
}

fn run(hash: String) -> Result(Nil, String) {
  use output <- result.try(
    cli_store.with_dets(".gleamunison/store.dets", fn(adapter) {
      case evidence.production_policy() {
        Ok(policy) -> Ok(report_with_policy(adapter, hash, policy))
        Error(_) -> Ok(report(adapter, hash))
      }
    }),
  )
  cli_result.success(output)
}

/// A plain-text attestation report for a subject hash. Tampered chunks are
/// excluded upstream by for_subject (integrity re-verified on read), so
/// everything rendered here is proof, not claims.
pub fn report(adapter: StorageAdapter, subject: String) -> String {
  report_with_policy(adapter, subject, evidence.AllowUnsigned)
}

pub fn report_with_policy(
  adapter: StorageAdapter,
  subject: String,
  policy: evidence.VerificationPolicy,
) -> String {
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
        evidence.verified_with_policy(adapter, subject, evidence.Test, policy)
      {
        True -> "verified: test evidence with passing verdict exists"
        False -> "verified: no passing test attestation"
      }
      let io_line = case
        evidence.verified_with_policy(adapter, subject, evidence.Io, policy)
      {
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
