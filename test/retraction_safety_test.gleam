import gleam/int
import gleam/list
import gleam/option.{Some}
import gleamunison/ast
import gleamunison/cli_purge
import gleamunison/cli_unpublish
import gleamunison/codebase
import gleamunison/dependency_snapshot
import gleamunison/identity.{Ref, hash_bytes, ref_hex}

import gleamunison/namespace
import gleamunison/publication_index
import gleamunison/storage
import gleeunit/should
import simplifile
import test_ffi.{pd_counter_get, pd_counter_inc, unique_integer}

fn target() {
  Ref(hash_bytes(<<"retraction-target">>))
}

pub fn absent_branch_does_not_hide_content_dependents_test() {
  let adapter = storage.inmemory()
  let definition = ast.TermDef(ast.RefTo(target()), ast.Builtin(ast.IntType))
  let ref = Ref(codebase.hash_of_definition(definition))
  let assert Ok(_) =
    codebase.insert(
      codebase.with_adapter(adapter),
      ast.Unit(ref, [#(ref, definition)]),
    )
  let assert Ok(snapshot) = dependency_snapshot.read(adapter, "main")
  dependency_snapshot.dependents(snapshot, target()) |> should.equal([ref])
}

pub fn failed_listing_is_not_an_empty_dependency_set_test() {
  let adapter = storage.inmemory()
  let assert Ok(_) = namespace.commit(adapter, "main", namespace.empty())
  let broken =
    storage.StorageAdapter(..adapter, list_refs: fn() {
      Error(storage.IoError("list failed"))
    })
  // A failed listing must surface as an Error, never an empty dependent set.
  dependency_snapshot.read(broken, "main")
  |> should.equal(
    Error(dependency_snapshot.StoreFailure(storage.IoError("list failed"))),
  )
}

pub fn failed_listing_is_not_an_empty_exclusive_closure_test() {
  let adapter = storage.inmemory()
  let assert Ok(_) = namespace.commit(adapter, "main", namespace.empty())
  let broken =
    storage.StorageAdapter(..adapter, list_refs: fn() {
      Error(storage.IoError("closure scan failed"))
    })
  // Same failure, closure question: an Error, never an empty closure.
  dependency_snapshot.read(broken, "main")
  |> should.equal(
    Error(
      dependency_snapshot.StoreFailure(storage.IoError("closure scan failed")),
    ),
  )
}

pub fn failed_branch_lookup_is_not_no_aliases_test() {
  let adapter = storage.inmemory()
  let broken =
    storage.StorageAdapter(..adapter, lookup: fn(_) {
      Error(storage.IoError("read failed"))
    })
  // The alias question never reaches an empty list: the read itself fails.
  let assert Error(_) = dependency_snapshot.read(broken, "main")
}

pub fn corrupt_candidate_does_not_disappear_from_safety_scan_test() {
  let adapter = storage.inmemory()
  let assert Ok(_) = namespace.commit(adapter, "main", namespace.empty())
  let corrupt = Ref(hash_bytes(<<"different bytes">>))
  let assert Ok(_) = adapter.insert(corrupt, <<"corrupt">>)
  dependency_snapshot.read(adapter, "main")
  |> should.equal(Error(dependency_snapshot.CorruptDefinition(corrupt)))
}

pub fn corrupt_branch_commit_must_refuse_before_any_write_test() {
  let adapter = storage.inmemory()
  let ptr = namespace.branch_pointer_ref("main")
  let assert Ok(_) = adapter.insert(ptr, <<"corrupt head">>)
  let assert Ok(before) = adapter.list_refs()
  let assert Error(_) = namespace.commit(adapter, "main", namespace.empty())
  adapter.lookup(ptr) |> should.equal(Ok(Some(<<"corrupt head">>)))
  adapter.list_refs() |> should.equal(Ok(before))
}

pub fn refused_retraction_preserves_index_namespace_and_bytes_test() {
  let adapter = storage.inmemory()
  let definition = ast.TermDef(ast.Int(99), ast.Builtin(ast.IntType))
  let ref = Ref(codebase.hash_of_definition(definition))
  let assert Ok(_) =
    codebase.insert(
      codebase.with_adapter(adapter),
      ast.Unit(ref, [#(ref, definition)]),
    )
  let ns = namespace.set(namespace.empty(), "kept", ref)
  let assert Ok(_) = namespace.commit(adapter, "main", ns)
  let path = "/tmp/retraction-safety-" <> int.to_string(unique_integer())
  let index = "kept " <> ref_hex(ref) <> "\n"
  let lines = publication_index.parse(index)
  let assert Ok(_) = simplifile.write(index, to: path)
  let assert Ok(before) = adapter.list_refs()
  let broken =
    storage.StorageAdapter(
      ..adapter,
      insert: fn(_, _) { panic as "refusal must not insert" },
      delete: fn(_) { panic as "refusal must not delete" },
    )
  let cases = [
    storage.StorageAdapter(..broken, list_refs: fn() {
      Error(storage.IoError("scan failed"))
    }),
    storage.StorageAdapter(..broken, lookup: fn(candidate) {
      case candidate == ref {
        True -> Error(storage.IoError("definition read failed"))
        False -> adapter.lookup(candidate)
      }
    }),
    storage.StorageAdapter(..broken, lookup: fn(candidate) {
      case candidate == namespace.branch_pointer_ref("main") {
        True -> Error(storage.IoError("branch read failed"))
        False -> adapter.lookup(candidate)
      }
    }),
  ]
  list.each(cases, fn(failed) {
    let assert Error(_) =
      cli_unpublish.retract(
        failed,
        path,
        "kept",
        ref_hex(ref),
        ref,
        "main",
        lines,
      )
    let assert Error(_) = cli_purge.purge(failed, path, ref, "main", True)
  })
  simplifile.read(path) |> should.equal(Ok(index))
  namespace.load_current(adapter, "main") |> should.equal(Ok(ns))
  adapter.list_refs() |> should.equal(Ok(before))
  let assert Ok(Some(_)) = adapter.lookup(ref)
  let assert Ok(_) = simplifile.delete(path)
}

pub fn snapshot_reads_store_once_for_all_closure_decisions_test() {
  let adapter = storage.inmemory()
  let leaf = ast.TermDef(ast.Int(100), ast.Builtin(ast.IntType))
  let leaf_ref = Ref(codebase.hash_of_definition(leaf))
  let root = ast.TermDef(ast.RefTo(leaf_ref), ast.Builtin(ast.IntType))
  let root_ref = Ref(codebase.hash_of_definition(root))
  let assert Ok(_) =
    codebase.insert(
      codebase.with_adapter(adapter),
      ast.Unit(root_ref, [#(leaf_ref, leaf), #(root_ref, root)]),
    )
  let observed =
    storage.StorageAdapter(..adapter, list_refs: fn() {
      let _ = pd_counter_inc(<<"snapshot-list-once">>)
      adapter.list_refs()
    })
  let assert Ok(snapshot) = dependency_snapshot.read(observed, "main")
  let removal = dependency_snapshot.exclusive_closure(snapshot, root_ref)
  list.length(removal) |> should.equal(2)
  list.contains(removal, leaf_ref) |> should.equal(True)
  dependency_snapshot.dependents(snapshot, leaf_ref) |> should.equal([root_ref])
  pd_counter_get(<<"snapshot-list-once">>) |> should.equal(1)
}
