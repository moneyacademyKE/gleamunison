import gleam/list
import gleamunison/identity.{type DefinitionRef, Ref, hash_bytes}
import gleamunison/namespace
import gleamunison/storage
import gleeunit/should

fn ref_tag(tag: String) -> DefinitionRef {
  Ref(hash_bytes(<<tag:utf8>>))
}

pub fn set_get_remove_pure_test() {
  let ns =
    namespace.empty()
    |> namespace.set("answer", ref_tag("v1"))
  namespace.get(ns, "answer") |> should.equal(Ok(ref_tag("v1")))
  namespace.get(ns, "missing") |> should.be_error
  let ns2 = namespace.remove(ns, "answer")
  namespace.get(ns2, "answer") |> should.be_error
}

pub fn save_load_roundtrip_test() {
  let store = storage.inmemory()
  let ns =
    namespace.empty()
    |> namespace.set("a", ref_tag("ra"))
    |> namespace.set("b", ref_tag("rb"))
  let assert Ok(ns_ref) = namespace.save(store, ns)
  let assert Ok(loaded) = namespace.load(store, ns_ref)
  namespace.get(loaded, "a") |> should.equal(Ok(ref_tag("ra")))
  namespace.get(loaded, "b") |> should.equal(Ok(ref_tag("rb")))
}

pub fn content_addressed_dedup_test() {
  let store = storage.inmemory()
  let ns1 = namespace.empty() |> namespace.set("x", ref_tag("rx"))
  let ns2 = namespace.empty() |> namespace.set("x", ref_tag("rx"))
  let assert Ok(r1) = namespace.save(store, ns1)
  let assert Ok(r2) = namespace.save(store, ns2)
  r1 |> should.equal(r2)
}

pub fn commit_advances_head_and_history_test() {
  let store = storage.inmemory()
  let ns1 = namespace.empty() |> namespace.set("x", ref_tag("rx1"))
  let assert Ok(_) = namespace.commit(store, "main", ns1)
  let ns2 = ns1 |> namespace.set("y", ref_tag("ry"))
  let assert Ok(_) = namespace.commit(store, "main", ns2)
  let assert Ok(#(seq, head_ref)) = namespace.branch_head(store, "main")
  seq |> should.equal(2)
  // Head points at the newest namespace
  let assert Ok(head_ns) = namespace.load(store, head_ref)
  namespace.get(head_ns, "y") |> should.equal(Ok(ref_tag("ry")))
  // History walks newest-first: seq 2 then seq 1
  let hist = namespace.history(store, "main")
  list.length(hist) |> should.equal(2)
  let assert [#(2, _), #(1, _)] = hist
}

pub fn branches_are_independent_test() {
  let store = storage.inmemory()
  let ns_a = namespace.empty() |> namespace.set("x", ref_tag("rxa"))
  let ns_b = namespace.empty() |> namespace.set("x", ref_tag("rxb"))
  let assert Ok(_) = namespace.commit(store, "a", ns_a)
  let assert Ok(_) = namespace.commit(store, "b", ns_b)
  let assert Ok(#(_, ref_a)) = namespace.branch_head(store, "a")
  let assert Ok(#(_, ref_b)) = namespace.branch_head(store, "b")
  should_not_equal(ref_a, ref_b)
}

fn should_not_equal(a: b, b: b) -> Nil {
  case a == b {
    True -> panic as "expected different values"
    False -> Nil
  }
}

pub fn diff_reports_changes_test() {
  let before =
    namespace.empty()
    |> namespace.set("keep", ref_tag("k"))
    |> namespace.set("change", ref_tag("old"))
    |> namespace.set("remove", ref_tag("gone"))
  let after =
    namespace.empty()
    |> namespace.set("keep", ref_tag("k"))
    |> namespace.set("change", ref_tag("new"))
    |> namespace.set("add", ref_tag("added"))
  let diff = namespace.diff(before, after)
  diff.added |> should.equal(["add"])
  diff.removed |> should.equal(["remove"])
  diff.changed |> should.equal(["change"])
}

pub fn merge_unions_disjoint_test() {
  let a = namespace.empty() |> namespace.set("x", ref_tag("rx"))
  let b = namespace.empty() |> namespace.set("y", ref_tag("ry"))
  let assert Ok(merged) = namespace.merge(a, b)
  namespace.get(merged, "x") |> should.equal(Ok(ref_tag("rx")))
  namespace.get(merged, "y") |> should.equal(Ok(ref_tag("ry")))
}

pub fn merge_detects_conflict_test() {
  let a = namespace.empty() |> namespace.set("x", ref_tag("rxa"))
  let b = namespace.empty() |> namespace.set("x", ref_tag("rxb"))
  let assert Error(conflicts) = namespace.merge(a, b)
  conflicts |> should.equal(["x"])
}

pub fn merge_agreeing_sides_ok_test() {
  let a = namespace.empty() |> namespace.set("x", ref_tag("same"))
  let b = namespace.empty() |> namespace.set("x", ref_tag("same"))
  let assert Ok(_) = namespace.merge(a, b)
}
