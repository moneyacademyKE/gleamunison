import gleam/list
import gleamunison/manifest
import gleamunison/storage
import gleeunit/should

fn sample() -> manifest.Manifest {
  let m =
    manifest.new("http-utils", "1.0.0")
    |> manifest.add_def("get-json", "aaa111")
    |> manifest.add_def("post-json", "bbb222")
    |> manifest.add_dep("ccc333")
  m
}

/// The manifest is content-addressed; same contents, same hash.
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
  |> list.map(fn(d) { #(manifest.def_name(d), manifest.def_hash(d)) })
  |> should.equal([#("get-json", "aaa111"), #("post-json", "bbb222")])
  parsed.deps |> should.equal(["ccc333"])
  parsed.require_evidence |> should.equal(True)
}

/// Current format preserves the effectful bit in the canonical payload.
pub fn manifest_effect_flags_round_trip_test() {
  let m =
    manifest.new("p", "1.0.0")
    |> manifest.add_def("pure", "aaa")
    |> manifest.add_def_with_effect("io", "bbb", True)
  let assert Ok(parsed) = manifest.parse(manifest.serialize(m))
  let assert [first, second] = parsed.defs
  manifest.def_name(first) |> should.equal("io")
  manifest.def_effectful(first) |> should.equal(True)
  manifest.def_name(second) |> should.equal("pure")
  manifest.def_effectful(second) |> should.equal(False)
}

/// Legacy manifests remain byte-canonical and conservative: missing flags mean pure.
pub fn legacy_manifest_defaults_defs_to_pure_test() {
  let text = "pkg:old:1.0.0:io=bbb::yes"
  let assert Ok(parsed) = manifest.parse(text)
  manifest.serialize(parsed) |> should.equal(text)
  let assert [def] = parsed.defs
  manifest.def_effectful(def) |> should.equal(False)
}

/// Current manifests reject ambiguous structural delimiters instead of
/// silently creating a non-round-trippable payload.
pub fn manifest_rejects_structural_delimiters_test() {
  manifest.parse("pkg:2:bad:name:1.0.0:: :yes") |> should.be_error
  manifest.parse("pkg:2:ok:1.0.0:name=hash=unknown::yes") |> should.be_error
  manifest.parse("pkg:2:ok:1.0.0:name=hash=pure,broken::yes")
  |> should.be_error
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

pub fn manifest_store_describes_storage_failure_test() {
  let adapter =
    storage.StorageAdapter(
      insert: fn(_, _) { Error(storage.IoError("disk offline")) },
      lookup: fn(_) { Error(storage.IoError("unused")) },
      delete: fn(_) { Error(storage.IoError("unused")) },
      list_refs: fn() { Error(storage.IoError("unused")) },
      close: fn() { Ok(Nil) },
    )

  manifest.store(adapter, sample())
  |> should.equal(Error("store manifest: io error: disk offline"))
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
