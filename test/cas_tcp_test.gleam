import gleam/option.{None, Some}
import gleamunison/codebase
import gleamunison/identity.{Ref, hash_bytes, hash_to_debug_string}
import gleamunison/storage
import gleeunit/should

@external(erlang, "gleamunison_cas_test", "tcp_push")
fn tcp_push(defs: List(#(String, BitArray))) -> Result(Nil, String)

@external(erlang, "gleamunison_cas_test", "tcp_invalid_message")
fn tcp_invalid_message(mode: Int) -> Bool

pub fn tcp_push_accepts_valid_blob_test() {
  let adapter = storage.inmemory()
  let bytes = <<"tcp-valid">>
  let hash = hash_bytes(bytes)
  tcp_push([#(hash_to_debug_string(hash), bytes)]) |> should.equal(Ok(Nil))
  adapter.lookup(Ref(hash)) |> should.equal(Ok(Some(bytes)))
}

pub fn tcp_push_propagates_admission_failure_test() {
  let adapter = storage.inmemory()
  let hash = hash_bytes(<<"tcp-honest">>)
  tcp_push([#(hash_to_debug_string(hash), <<"tcp-forged">>)]) |> should.be_error
  adapter.lookup(Ref(hash)) |> should.equal(Ok(None))
}

pub fn tcp_push_does_not_rewrite_existing_artifact_test() {
  let adapter = storage.inmemory()
  let bytes = <<"tcp-existing">>
  let hash = hash_bytes(bytes)
  storage.insert_content(adapter, Ref(hash), bytes) |> should.equal(Ok(Nil))
  tcp_push([#(hash_to_debug_string(hash), <<"tcp-forged">>)]) |> should.be_error
  adapter.lookup(Ref(hash)) |> should.equal(Ok(Some(bytes)))
}

pub fn tcp_rejects_compressed_messages_test() {
  tcp_invalid_message(0) |> should.be_true
}

pub fn tcp_rejects_trailing_message_bytes_test() {
  tcp_invalid_message(1) |> should.be_true
}

pub fn legacy_raw_wrapper_does_not_admit_forged_content_test() {
  let cb = codebase.empty()
  let ref = Ref(hash_bytes(<<"legacy honest">>))
  let cb = codebase.insert_raw(cb, ref, <<"legacy forged">>)
  codebase.get_adapter(cb).lookup(ref) |> should.equal(Ok(None))
}

pub fn partitioned_storage_invalid_path_is_reported_test() {
  storage.partitioned_dets("gleam.toml/not-a-directory") |> should.be_error
}
