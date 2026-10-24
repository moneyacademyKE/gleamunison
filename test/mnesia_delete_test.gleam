import gleam/list
import gleam/option.{None, Some}
import gleamunison/identity.{Ref, hash_bytes}
import gleamunison/storage
import gleeunit/should

pub fn mnesia_delete_removes_only_the_record_and_is_idempotent_test() {
  let assert Ok(adapter) = storage.mnesia("audit_delete_contract")
  let removed = Ref(hash_bytes(<<"mnesia-removed">>))
  let kept = Ref(hash_bytes(<<"mnesia-kept">>))
  let assert Ok(_) = adapter.insert(removed, <<"payload">>)
  let assert Ok(_) = adapter.insert(kept, <<"keep">>)
  adapter.delete(removed) |> should.equal(Ok(Nil))
  adapter.lookup(removed) |> should.equal(Ok(None))
  let assert Ok(refs) = adapter.list_refs()
  list.contains(refs, removed) |> should.equal(False)
  adapter.lookup(kept) |> should.equal(Ok(Some(<<"keep">>)))
  adapter.delete(removed) |> should.equal(Ok(Nil))
  adapter.close() |> should.equal(Ok(Nil))
}

@external(erlang, "gleamunison_storage", "mnesia_delete")
fn delete_from_absent_table(
  table: Int,
  key: BitArray,
) -> Result(Nil, storage.StorageError)

pub fn mnesia_delete_propagates_transaction_abort_test() {
  let assert Error(storage.StorageError(_)) =
    delete_from_absent_table(0, <<"key">>)
}
