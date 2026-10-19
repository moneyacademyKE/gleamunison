import gleam/bit_array
import gleam/list
import gleam/option.{None, Some}
import gleamunison/identity.{Ref, hash_bytes}
import gleamunison/namespace
import gleamunison/storage
import gleeunit/should

pub fn namespace_load_rehashes_bytes_test() {
  let adapter = storage.inmemory()
  let assert Ok(ref) = namespace.save(adapter, namespace.empty())
  let different =
    namespace.empty() |> namespace.set("x", Ref(hash_bytes(<<1>>)))
  let assert Ok(other) = namespace.save(adapter, different)
  let assert Ok(Some(bytes)) = adapter.lookup(other)
  let assert Ok(_) = adapter.insert(ref, bytes)
  namespace.load(adapter, ref) |> should.be_error
}

pub fn cross_branch_pointer_rejected_before_any_write_test() {
  let src = storage.inmemory()
  let dst = storage.inmemory()
  let assert Ok(_) = namespace.commit(src, "other", namespace.empty())
  let assert Ok(chunks) = namespace.export_branch(src, "other")
  let wrong =
    list.map(chunks, fn(pair) {
      case pair.0 {
        "pointer:other" -> #("pointer:main", pair.1)
        _ -> pair
      }
    })
  namespace.import_branch(dst, wrong) |> should.be_error
  dst.list_refs() |> should.equal(Ok([]))
}

pub fn branch_read_checks_embedded_name_test() {
  let adapter = storage.inmemory()
  let assert Ok(_) = namespace.commit(adapter, "other", namespace.empty())
  let assert Ok(Some(bytes)) =
    adapter.lookup(namespace.branch_pointer_ref("other"))
  let assert Ok(_) = adapter.insert(namespace.branch_pointer_ref("main"), bytes)
  namespace.branch_head(adapter, "main") |> should.be_error
}

pub fn import_storage_failure_never_publishes_pointer_test() {
  let src = storage.inmemory()
  let dst = storage.inmemory()
  let assert Ok(_) = namespace.commit(src, "main", namespace.empty())
  let assert Ok(chunks) = namespace.export_branch(src, "main")
  let ordered_pointer_first = list.reverse(chunks)
  let adapter =
    storage.StorageAdapter(..dst, insert: fn(ref, bytes) {
      case ref == namespace.branch_pointer_ref("main") {
        True -> dst.insert(ref, bytes)
        False -> Error(storage.IoError("injected chunk write failure"))
      }
    })
  namespace.import_branch(adapter, ordered_pointer_first) |> should.be_error
  dst.lookup(namespace.branch_pointer_ref("main")) |> should.equal(Ok(None))
}

pub fn malformed_embedded_ref_fails_without_exception_test() {
  let adapter = storage.inmemory()
  let bytes = bit_array.from_string("ns\n1\neA==:nope")
  let ref = Ref(hash_bytes(bytes))
  let assert Ok(_) = adapter.insert(ref, bytes)
  namespace.load(adapter, ref) |> should.be_error
}
