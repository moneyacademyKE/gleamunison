import gleam/int
import gleam/list
import gleamunison/cli_evidence
import gleamunison/evidence
import gleamunison/storage
import gleamunison/trust
import gleamunison/turnstile
import gleeunit/should
import test_ffi.{pd_counter_get, pd_counter_inc}

fn observed(adapter: storage.StorageAdapter, key: BitArray) {
  storage.StorageAdapter(..adapter, list_refs: fn() {
    let _ = pd_counter_inc(key)
    adapter.list_refs()
  })
}

pub fn many_definition_gate_reads_one_evidence_snapshot_test() {
  let adapter = storage.inmemory()
  let defs =
    list.map([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], fn(n) {
      let subject = int.to_string(n)
      let assert Ok(_) =
        evidence.attach(
          adapter,
          subject: subject,
          kind: evidence.Io,
          verdict: "approved",
          payload: "seen",
          ts: n,
        )
      #("def-" <> subject, subject, True)
    })
  turnstile.check(observed(adapter, <<"gate-scan-once">>), defs)
  |> should.equal(Ok(list.map(defs, fn(d) { d.0 })))
  pd_counter_get(<<"gate-scan-once">>) |> should.equal(1)
}

pub fn report_reads_one_snapshot_for_records_test_and_io_test() {
  let adapter = storage.inmemory()
  let assert Ok(_) =
    evidence.attach(
      adapter,
      subject: "subject",
      kind: evidence.Test,
      verdict: "pass",
      payload: "ok",
      ts: 1,
    )
  let _ =
    cli_evidence.report_with_policy(
      observed(adapter, <<"report-scan-once">>),
      "subject",
      trust.FixturesOnly,
    )
  pd_counter_get(<<"report-scan-once">>) |> should.equal(1)
}

pub fn evidence_gate_refuses_failed_reads_test() {
  let adapter = storage.inmemory()
  let broken =
    storage.StorageAdapter(..adapter, list_refs: fn() {
      Error(storage.IoError("read failed"))
    })
  turnstile.check(broken, [#("def", "subject", True)])
  |> should.equal(Error(["def"]))
}

pub fn evidence_snapshot_preserves_storage_failure_test() {
  let adapter = storage.inmemory()
  let broken =
    storage.StorageAdapter(..adapter, list_refs: fn() {
      Error(storage.IoError("evidence scan failed"))
    })
  evidence.snapshot(broken)
  |> should.equal(Error(storage.IoError("evidence scan failed")))
}

pub fn evidence_snapshot_rejects_a_listed_but_missing_chunk_test() {
  let adapter = storage.inmemory()
  let assert Ok(#(ref, _)) =
    evidence.attach(
      adapter,
      subject: "subject",
      kind: evidence.Test,
      verdict: "pass",
      payload: "ok",
      ts: 1,
    )
  let assert Ok(Nil) = adapter.delete(ref)
  let missing = storage.StorageAdapter(..adapter, list_refs: fn() { Ok([ref]) })
  evidence.snapshot(missing)
  |> should.equal(Error(storage.NotFound))
}
