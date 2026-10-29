//// `gleamunison evidence <hash>` — list the integrity-checked attestations
//// for a subject hash. "Did you test it?" becomes a lookup, not a promise.
////
//// `gleamunison evidence attest <hash> io <note...>` — human attestation
//// for effectful defs. Only `io` is attestable by hand: test/review/
//// property evidence must come from the tools that ran them.

import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import gleamunison/cli_lifecycle
import gleamunison/cli_result
import gleamunison/cli_store
import gleamunison/datetime
import gleamunison/evidence
import gleamunison/identity
import gleamunison/storage.{type StorageAdapter}
import gleamunison/trust

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
      // The subject is a content hash. `zzz` used to be accepted and attested
      // to, producing a record that can never cover anything: a typo that
      // reports success is worse than a typo that stops.
      use _ <- result.try(
        identity.parse_ref_hex(hash)
        |> result.replace_error(
          "evidence attest: '"
          <> hash
          <> "' is not a content hash (expected 64 hex digits)",
        ),
      )
      use signer <- result.try(evidence.production_signer())
      use context <- result.try(cli_lifecycle.resolve_context(None))
      let store_path = cli_lifecycle.store_path(context)
      use output <- result.try(
        cli_store.with_dets(store_path, fn(adapter) {
          evidence.attach_signed(
            adapter,
            signer,
            subject: hash,
            kind: evidence.Io,
            verdict: "approved",
            payload: note,
            ts: datetime.now_unix(),
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
  // Same rule as attest: a subject is a content hash. Asking for the evidence
  // on `zzz` reported a record and exited 0, so a mistyped lookup looked like
  // an answered question.
  use _ <- result.try(
    identity.parse_ref_hex(hash)
    |> result.replace_error(
      "evidence: '"
      <> hash
      <> "' is not a content hash (expected 64 hex digits)",
    ),
  )
  use context <- result.try(cli_lifecycle.resolve_context(None))
  let store_path = cli_lifecycle.store_path(context)
  use output <- result.try(
    cli_store.with_dets(store_path, fn(adapter) {
      case trust.production_policy() {
        Ok(policy) -> Ok(report_with_policy(adapter, hash, policy))
        // No signing key means no production policy exists to enforce. The
        // report names that rather than implying the records were checked.
        Error(_) -> Ok(report_with_policy(adapter, hash, trust.FixturesOnly))
      }
    }),
  )
  cli_result.success(output)
}

/// A plain-text attestation report for a subject hash. Tampered chunks are
/// excluded upstream by evidence.snapshot (integrity re-verified on read), so
/// everything rendered here is proof, not claims.
pub fn report(adapter: StorageAdapter, subject: String) -> String {
  report_with_policy(adapter, subject, trust.FixturesOnly)
}

pub fn report_with_policy(
  adapter: StorageAdapter,
  subject: String,
  policy: trust.TrustPolicy,
) -> String {
  case evidence.snapshot(adapter) {
    Error(_) -> "cannot read evidence for " <> subject
    Ok(snapshot) -> report_snapshot(snapshot, subject, policy)
  }
}

fn report_snapshot(
  snapshot: evidence.Snapshot,
  subject: String,
  policy: trust.TrustPolicy,
) -> String {
  let records = evidence.from_snapshot(snapshot, subject)
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
        trust.verified_in(snapshot, subject, evidence.Test, policy)
      {
        Ok(_) -> "test: admitted by the policy"
        Error(refusal) ->
          "test: refused (" <> trust.refusal_name(refusal) <> ")"
      }
      let io_line = case
        trust.verified_in(snapshot, subject, evidence.Io, policy)
      {
        Ok(_) -> "io: admitted by the policy"
        Error(refusal) -> "io: refused (" <> trust.refusal_name(refusal) <> ")"
      }
      string.join(
        [
          "evidence for " <> subject <> ":",
          ..list.append(lines, [
            "policy: " <> trust.describe(policy),
            verified_line,
            io_line,
          ])
        ],
        "\n",
      )
    }
  }
}
