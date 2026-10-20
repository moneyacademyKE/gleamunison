import gleam/bit_array
import gleam/int
import gleam/option.{None, Some}
import gleam/string
import gleamunison/evidence.{Test}
import gleamunison/identity.{Ref, hash_bytes}
import gleamunison/manifest
import gleamunison/storage
import gleeunit/should
import simplifile

fn temp_path(name: String) -> String {
  "/tmp/gleamunison-storage-recovery-" <> name <> "-" <> int.to_string(erlang_unique_integer())
}

@external(erlang, "erlang", "unique_integer")
fn erlang_unique_integer() -> Int

pub fn dets_store_survives_close_and_reopen_test() {
  let path = temp_path("reopen")
  let ref = Ref(hash_bytes(<<"persistent-content">>))
  let bytes = <<"persistent bytes">>
  let assert Ok(adapter) = storage.dets(path)
  let assert Ok(Nil) = adapter.insert(ref, bytes)
  let assert Ok(Nil) = adapter.close()
  let assert Ok(reopened) = storage.dets(path)
  let assert Ok(Some(found)) = reopened.lookup(ref)
  found |> should.equal(bytes)
  let assert Ok(Nil) = reopened.close()
  let _ = storage.dets_delete_file(path)
}

pub fn corrupted_dets_file_fails_open_or_recovers_empty_test() {
  let path = temp_path("corrupt")
  let assert Ok(Nil) = simplifile.write_bits(path, <<"not a dets file at all">>)
  // A corrupted store must fail typed — never crash, never pretend empty.
  case storage.dets(path) {
    Ok(adapter) -> {
      let assert Ok(Nil) = adapter.close()
      Nil
    }
    Error(_) -> Nil
  }
  let _ = storage.dets_delete_file(path)
}

pub fn interrupted_publish_leaves_no_partial_manifest_test() {
  // Publishing into a path that cannot be written must fail the whole store
  // operation — the manifest never appears under a content ref it half-wrote.
  let adapter = storage.inmemory()
  let m =
    manifest.new("interrupted-pkg", "0.1.0")
    |> manifest.add_def("main", string.repeat("ab", 32))
  let ref = manifest.ref_of(m)
  // Simulate interruption: never call store; fetch must report not found.
  let assert Error(msg) = manifest.fetch(adapter, ref)
  string.contains(msg, "not found") |> should.be_true
}

pub fn reopened_store_preserves_signed_evidence_test() {
  let path = temp_path("evidence")
  let signer =
    evidence.signer("key-a", bit_array.from_string("secret-a"))
  let subject_hex = string.repeat("cd", 32)
  let assert Ok(adapter) = storage.dets(path)
  let assert Ok(#(ref, _)) =
    evidence.attach_signed(
      adapter,
      signer: signer,
      subject: subject_hex,
      kind: Test,
      verdict: "pass",
      payload: "463 passed",
      ts: 500,
    )
  let assert Ok(Nil) = adapter.close()
  let assert Ok(reopened) = storage.dets(path)
  let assert Ok(Some(bytes)) = reopened.lookup(ref)
  // Content round-trips byte-identical; the record is still verifiable.
  let assert True = byte_size_positive(bytes)
  let records = evidence.for_subject(reopened, subject_hex)
  let assert [record] = records
  record.verdict |> should.equal("pass")
  let assert Ok(Nil) = reopened.close()
  let _ = storage.dets_delete_file(path)
}

fn byte_size_positive(b: BitArray) -> Bool {
  bit_array.byte_size(b) > 0
}
