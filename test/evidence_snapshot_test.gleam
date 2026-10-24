import gleam/int
import gleam/list
import gleamunison/cli_evidence
import gleamunison/evidence
import gleamunison/storage
import gleamunison/trust
import gleamunison/turnstile
import gleeunit/should

@external(erlang, "gleamunison_ffi_test", "pd_counter_inc")
fn increment(key: BitArray) -> Int

@external(erlang, "gleamunison_ffi_test", "pd_counter_get")
fn count(key: BitArray) -> Int

fn observed(adapter: storage.StorageAdapter, key: BitArray) {
  storage.StorageAdapter(..adapter, list_refs: fn() {
    let _ = increment(key)
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
  count(<<"gate-scan-once">>) |> should.equal(1)
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
  count(<<"report-scan-once">>) |> should.equal(1)
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
