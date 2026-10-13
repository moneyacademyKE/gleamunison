import gleam/list
import gleamunison/manifest
import gleamunison/storage
import gleeunit/should

fn sample() -> manifest.Manifest {
  manifest.new("http-utils", "1.0.0")
  |> manifest.add_def("get-json", "aaa111")
  |> manifest.add_def("post-json", "bbb222")
  |> manifest.add_dep("ccc333")
}

/// The manifest is content-addressed: same contents, same hash.
pub fn manifest_hash_is_content_addressed_test() {
  let a = sample()
  let b = sample()
  manifest.hash_of(a) |> should.equal(manifest.hash_of(b))

  let c = manifest.add_def(a, "extra", "ddd444")
  should.not_equal(manifest.hash_of(a), manifest.hash_of(c))
}

/// Serialize → parse is a lossless round trip.
pub fn manifest_round_trip_test() {
  let m = sample()
  let text = manifest.serialize(m)
  let assert Ok(parsed) = manifest.parse(text)
  parsed.name |> should.equal("http-utils")
  parsed.version |> should.equal("1.0.0")
  parsed.defs
  |> should.equal([#("get-json", "aaa111"), #("post-json", "bbb222")])
  parsed.deps |> should.equal(["ccc333"])
  parsed.require_evidence |> should.equal(True)
}

/// Store by hash, fetch by hash: the DAG is the registry.
pub fn manifest_store_fetch_test() {
  let adapter = storage.inmemory()
  let m = sample()
  let assert Ok(ref) = manifest.store(adapter, m)
  let assert Ok(fetched) = manifest.fetch(adapter, ref)
  fetched.name |> should.equal(m.name)
  fetched.defs |> should.equal(m.defs)
  manifest.hash_of(fetched) |> should.equal(manifest.hash_of(m))
}

/// Parse rejects garbage.
pub fn manifest_parse_rejects_garbage_test() {
  manifest.parse("not a manifest") |> should.be_error
}

/// Defs are listed in insertion order but hashing is order-independent:
/// same set, any order, same hash.
pub fn manifest_hash_order_independent_test() {
  let a =
    manifest.new("p", "1.0.0")
    |> manifest.add_def("x", "111")
    |> manifest.add_def("y", "222")
  let b =
    manifest.new("p", "1.0.0")
    |> manifest.add_def("y", "222")
    |> manifest.add_def("x", "111")
  manifest.hash_of(a) |> should.equal(manifest.hash_of(b))
  // serialize is canonical (sorted) so stored bytes are identical too
  manifest.serialize(a) |> should.equal(manifest.serialize(b))
  let _ = list.length(a.defs)
}
