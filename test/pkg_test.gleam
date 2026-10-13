import gleam/list
import gleam/string
import gleamunison/evidence
import gleamunison/manifest
import gleamunison/namespace
import gleamunison/pkg
import gleamunison/storage
import gleeunit/should

fn seeded_store() -> #(storage.StorageAdapter, manifest.Manifest, String) {
  let adapter = storage.inmemory()
  let m =
    manifest.new("http-utils", "1.0.0")
    |> manifest.add_def("get-json", "aaa111")
    |> manifest.add_def("post-json", "bbb222")
  let assert Ok(ref) = manifest.store(adapter, m)
  let hex = manifest.ref_hex_of(ref)
  #(adapter, m, hex)
}

/// Install refuses when a gated def lacks passing-test evidence, and the
/// refusal names the unevidenced definitions.
pub fn install_refuses_unevidenced_defs_test() {
  let #(adapter, _m, hex) = seeded_store()
  let assert Error(msg) = pkg.install_from_store(adapter, hex, "main")
  string.contains(msg, "get-json") |> should.be_true
  string.contains(msg, "post-json") |> should.be_true
}

/// Install admits a fully-attested package and binds its names on the branch.
pub fn install_admits_evidenced_package_test() {
  let #(adapter, _m, hex) = seeded_store()
  let assert Ok(_) =
    evidence.attach(adapter, "aaa111", evidence.Test, "pass", "{}", 1)
  let assert Ok(_) =
    evidence.attach(adapter, "bbb222", evidence.Test, "pass", "{}", 1)
  let assert Ok(installed) = pkg.install_from_store(adapter, hex, "main")
  list.contains(installed, "get-json") |> should.be_true
  list.contains(installed, "post-json") |> should.be_true

  // The branch actually carries the bindings.
  let assert Ok(ns) = namespace.load_current(adapter, "main")
  namespace.get(ns, "get-json") |> should.be_ok
  namespace.get(ns, "post-json") |> should.be_ok
}

/// require_evidence = false skips the gate entirely.
pub fn install_without_evidence_requirement_test() {
  let adapter = storage.inmemory()
  let m =
    manifest.new("quick-lib", "0.1.0")
    |> manifest.add_def("helper", "ccc333")
    |> manifest.without_evidence_requirement
  let assert Ok(ref) = manifest.store(adapter, m)
  let hex = manifest.ref_hex_of(ref)
  let assert Ok(installed) = pkg.install_from_store(adapter, hex, "main")
  installed |> should.equal(["helper"])
}

/// Unknown manifest hash: clean error, no namespace writes.
pub fn install_unknown_manifest_errors_test() {
  let adapter = storage.inmemory()
  let assert Error(msg) = pkg.install_from_store(adapter, "deadbeef", "main")
  string.contains(msg, "manifest") |> should.be_true
  case namespace.load_current(adapter, "main") {
    Error(_) -> Nil
    Ok(_) -> should.fail()
  }
}

/// Publish runs the turnstile: an unevidenced def refuses, and the refusal
/// names it.
pub fn publish_refuses_unevidenced_test() {
  let adapter = storage.inmemory()
  let pairs = [#("get-json", "aaa111")]
  let assert Error(missing) =
    pkg.publish_to_store(adapter, pairs, "http-utils", "1.0.0")
  list.contains(missing, "get-json") |> should.be_true
}

/// Publish of attested defs stores the manifest and returns its hash —
/// the hash is fetchable and carries the same def set.
pub fn publish_stores_fetchable_manifest_test() {
  let adapter = storage.inmemory()
  let pairs = [#("get-json", "aaa111"), #("post-json", "bbb222")]
  let assert Ok(_) =
    evidence.attach(adapter, "aaa111", evidence.Test, "pass", "{}", 1)
  let assert Ok(_) =
    evidence.attach(adapter, "bbb222", evidence.Test, "pass", "{}", 1)
  let assert Ok(hex) =
    pkg.publish_to_store(adapter, pairs, "http-utils", "1.0.0")
  let assert Ok(m) = manifest.fetch(adapter, manifest.ref_from_hex(hex))
  m.name |> should.equal("http-utils")
  m.version |> should.equal("1.0.0")
  m.defs |> should.equal(pairs)
  m.require_evidence |> should.equal(True)
}
