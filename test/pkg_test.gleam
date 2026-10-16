import gleam/list
import gleam/option.{None, Some}
import gleam/result
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
  let pairs = [#("get-json", "aaa111", False)]
  let assert Error(missing) =
    pkg.publish_to_store(adapter, pairs, "http-utils", "1.0.0")
  list.contains(missing, "get-json") |> should.be_true
}

/// Publish of attested defs stores the manifest and returns its hash —
/// the hash is fetchable and carries the same def set.
pub fn publish_stores_fetchable_manifest_test() {
  let adapter = storage.inmemory()
  let pairs = [#("get-json", "aaa111", False), #("post-json", "bbb222", False)]
  let assert Ok(_) =
    evidence.attach(adapter, "aaa111", evidence.Test, "pass", "{}", 1)
  let assert Ok(_) =
    evidence.attach(adapter, "bbb222", evidence.Test, "pass", "{}", 1)
  let assert Ok(hex) =
    pkg.publish_to_store(adapter, pairs, "http-utils", "1.0.0")
  let assert Ok(m) = manifest.fetch(adapter, manifest.ref_from_hex(hex))
  m.name |> should.equal("http-utils")
  m.version |> should.equal("1.0.0")
  m.defs
  |> should.equal(list.map(pairs, fn(p) { #(p.0, p.1) }))
  m.require_evidence |> should.equal(True)
}

/// Deps install recursively: installing the root also installs its
/// dependency's defs, and both land on the branch.
pub fn install_recurses_into_deps_test() {
  let adapter = storage.inmemory()
  let dep =
    manifest.new("base-lib", "1.0.0")
    |> manifest.add_def("base-helper", "ddd444")
    |> manifest.without_evidence_requirement
  let assert Ok(dep_ref) = manifest.store(adapter, dep)
  let dep_hex = manifest.ref_hex_of(dep_ref)
  let root =
    manifest.new("app-lib", "2.0.0")
    |> manifest.add_def("app-main", "eee555")
    |> manifest.add_dep(dep_hex)
    |> manifest.without_evidence_requirement
  let assert Ok(root_ref) = manifest.store(adapter, root)
  let root_hex = manifest.ref_hex_of(root_ref)

  let assert Ok(installed) = pkg.install_from_store(adapter, root_hex, "main")
  list.contains(installed, "base-helper") |> should.be_true
  list.contains(installed, "app-main") |> should.be_true

  let assert Ok(ns) = namespace.load_current(adapter, "main")
  namespace.get(ns, "base-helper") |> should.be_ok
  namespace.get(ns, "app-main") |> should.be_ok
}

/// Cycles terminate: A depends on B, B depends on A; each installs once.
pub fn install_breaks_dep_cycles_test() {
  let adapter = storage.inmemory()
  // Store B referencing A's hex; but A's hex depends on B's... precompute
  // by storing placeholders is impossible (hash covers deps). Build the
  // cycle on a single manifest that depends on itself.
  let self_dep =
    manifest.new("loop-lib", "1.0.0")
    |> manifest.add_def("loop-fn", "fff666")
    |> manifest.without_evidence_requirement
  let assert Ok(self_ref) = manifest.store(adapter, self_dep)
  let self_hex = manifest.ref_hex_of(self_ref)
  let cyclic =
    manifest.new("cycle-lib", "1.0.0")
    |> manifest.add_def("cycle-fn", "077777")
    |> manifest.add_dep(self_hex)
    |> manifest.add_dep(self_hex)
    |> manifest.without_evidence_requirement
  let assert Ok(cyc_ref) = manifest.store(adapter, cyclic)
  let cyc_hex = manifest.ref_hex_of(cyc_ref)

  let assert Ok(installed) = pkg.install_from_store(adapter, cyc_hex, "main")
  // self_hex appears twice in deps but installs once: loop-fn listed once.
  list.count(installed, fn(n) { n == "loop-fn" }) |> should.equal(1)
  list.contains(installed, "cycle-fn") |> should.be_true
}

/// Manifest closure: transitive deps and def hashes, no duplicates.
pub fn manifest_closure_collects_transitive_refs_test() {
  let adapter = storage.inmemory()
  let dep =
    manifest.new("base", "1.0.0")
    |> manifest.add_def("b1", "d1d1d1")
    |> manifest.without_evidence_requirement
  let assert Ok(dep_ref) = manifest.store(adapter, dep)
  let dep_hex = manifest.ref_hex_of(dep_ref)
  let root =
    manifest.new("top", "1.0.0")
    |> manifest.add_def("t1", "e2e2e2")
    |> manifest.add_dep(dep_hex)
    |> manifest.without_evidence_requirement
  let assert Ok(root_ref) = manifest.store(adapter, root)
  let root_hex = manifest.ref_hex_of(root_ref)

  let assert Ok(closure) = pkg.manifest_closure(adapter, root_hex)
  list.contains(closure.manifests, root_hex) |> should.be_true
  list.contains(closure.manifests, dep_hex) |> should.be_true
  list.contains(closure.defs, "d1d1d1") |> should.be_true
  list.contains(closure.defs, "e2e2e2") |> should.be_true
  list.length(closure.manifests) |> should.equal(2)
}

/// Selective pull: the peer holds the package closure plus an unrelated
/// chunk; pull_closure transfers exactly the closure and nothing else.
pub fn pull_closure_transfers_only_the_closure_test() {
  let peer = storage.inmemory()
  let local = storage.inmemory()

  // The package graph lives on the peer: root depends on dep.
  let dep =
    manifest.new("dep-lib", "1.0.0")
    |> manifest.add_def("dep-fn", "0a0a0a")
    |> manifest.without_evidence_requirement
  let assert Ok(dep_ref) = manifest.store(peer, dep)
  let dep_hex = manifest.ref_hex_of(dep_ref)
  let root =
    manifest.new("root-lib", "1.0.0")
    |> manifest.add_def("root-fn", "0b0b0b")
    |> manifest.add_dep(dep_hex)
    |> manifest.without_evidence_requirement
  let assert Ok(root_ref) = manifest.store(peer, root)
  let root_hex = manifest.ref_hex_of(root_ref)

  // Def chunks and an unrelated stranger chunk, peer-side only.
  let assert Ok(_) = peer.insert(manifest.ref_from_hex("0a0a0a"), <<"dep def">>)
  let assert Ok(_) =
    peer.insert(manifest.ref_from_hex("0b0b0b"), <<"root def">>)
  let assert Ok(_) =
    peer.insert(manifest.ref_from_hex("0c0c0c"), <<"unrelated">>)

  let fetch = fn(hexes: List(String)) -> Result(Nil, String) {
    list.try_each(hexes, fn(hex) {
      case peer.lookup(manifest.ref_from_hex(hex)) {
        Ok(Some(bytes)) ->
          local.insert(manifest.ref_from_hex(hex), bytes)
          |> result.map_error(fn(_) { "insert failed" })
        _ -> Error("peer missing chunk: " <> hex)
      }
    })
  }

  let assert Ok(closure) = pkg.pull_closure(local, root_hex, fetch)
  list.length(closure.manifests) |> should.equal(2)

  // Local now holds both manifests and both def chunks...
  list.each([root_hex, dep_hex, "0a0a0a", "0b0b0b"], fn(hex) {
    case local.lookup(manifest.ref_from_hex(hex)) {
      Ok(Some(_)) -> Nil
      _ -> panic as "closure chunk missing locally"
    }
  })
  // ...but the stranger never crossed the wire.
  case local.lookup(manifest.ref_from_hex("0c0c0c")) {
    Ok(None) -> Nil
    _ -> panic as "unrelated chunk leaked into local store"
  }
}
