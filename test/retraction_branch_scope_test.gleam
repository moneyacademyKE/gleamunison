//// Retraction is scoped to a branch; content is not. `unpublish` and `purge`
//// remove bytes from the store, which every branch shares, while their safety
//// scan reads one branch's namespace. So a name bound on `dev` looked absent
//// from `main`, and retracting it on `main` deleted content `dev` still
//// resolved to — leaving a binding to a ref nobody can load, which is the exact
//// lie these commands exist to prevent.

import gleam/int
import gleam/option.{None, Some}
import gleam/string
import gleamunison/ast
import gleamunison/branch_scope
import gleamunison/cli_purge
import gleamunison/cli_result
import gleamunison/cli_unpublish
import gleamunison/codebase
import gleamunison/identity.{Ref, hash_from_bytes, ref_hex}
import gleamunison/namespace
import gleamunison/publication_index
import gleamunison/storage
import gleeunit/should
import simplifile
import test_ffi.{unique_integer}

fn seeded() {
  let adapter = storage.inmemory()
  let definition = ast.TermDef(ast.Int(7), ast.Builtin(ast.IntType))
  let ref = Ref(codebase.hash_of_definition(definition))
  let assert Ok(_) =
    codebase.insert(
      codebase.with_adapter(adapter),
      ast.Unit(ref, [#(ref, definition)]),
    )
  #(adapter, ref)
}

fn index_text(name: String, ref) -> String {
  name <> " " <> ref_hex(ref) <> "\n"
}

/// The lines the CLI would have read from `index_file`'s bytes, parsed by the
/// same owner the command uses — so this test cannot drift from the format.
fn index_lines(name: String, ref) -> List(publication_index.Line) {
  publication_index.parse(index_text(name, ref))
}

fn index_file(name: String, ref) -> String {
  let path = "/tmp/retraction-scope-" <> int.to_string(unique_integer())
  let assert Ok(_) = simplifile.write(index_text(name, ref), to: path)
  path
}

/// The store knows which branches exist; nothing had asked it.
pub fn branches_are_discoverable_from_the_store_test() {
  let #(adapter, ref) = seeded()
  let assert Ok(_) = namespace.commit(adapter, "main", namespace.empty())
  let assert Ok(_) =
    namespace.commit(adapter, "dev", namespace.set(namespace.empty(), "x", ref))
  branch_scope.branches(adapter)
  |> should.equal(Ok(["dev", "main"]))
}

fn vanished_branch() {
  let adapter = storage.inmemory()
  let pointer = namespace.branch_pointer_ref("vanished")
  let assert Ok(Nil) = adapter.insert(pointer, <<>>)
  let assert Ok(refs) = adapter.list_refs()
  let assert True = refs == [pointer]
  let assert Ok(Nil) = adapter.delete(pointer)
  storage.StorageAdapter(..adapter, list_refs: fn() { Ok(refs) })
}

pub fn branches_reject_a_listed_but_missing_chunk_test() {
  branch_scope.branches(vanished_branch())
  |> should.equal(Error("branch pointer missing"))
}

pub fn branch_bindings_reject_a_listed_but_missing_chunk_test() {
  branch_scope.branches_binding(vanished_branch(), Ref(hash_from_bytes(<<>>)))
  |> should.equal(Error("branch pointer missing"))
}

/// Names bound to this content, on every branch, not just the selected one.
pub fn bindings_span_branches_test() {
  let #(adapter, ref) = seeded()
  let assert Ok(_) =
    namespace.commit(
      adapter,
      "main",
      namespace.set(namespace.empty(), "a", ref),
    )
  let assert Ok(_) =
    namespace.commit(adapter, "dev", namespace.set(namespace.empty(), "b", ref))
  branch_scope.branches_binding(adapter, ref)
  |> should.equal(Ok([#("dev", "b"), #("main", "a")]))
}

/// Two branches binding the same content cannot both retract first, so a
/// refusal here is a deadlock. The name is branch-scoped and goes; the bytes are
/// shared and stay, because another branch still resolves to them. Deleting them
/// would leave that branch's binding pointing at nothing.
pub fn unpublish_retracts_the_name_and_keeps_shared_bytes_test() {
  let #(adapter, ref) = seeded()
  let assert Ok(_) =
    namespace.commit(
      adapter,
      "main",
      namespace.set(namespace.empty(), "a", ref),
    )
  let assert Ok(_) =
    namespace.commit(adapter, "dev", namespace.set(namespace.empty(), "a", ref))
  let path = index_file("a", ref)
  let lines = index_lines("a", ref)
  let assert Ok(message) =
    cli_unpublish.retract(adapter, path, "a", ref_hex(ref), ref, "main", lines)
  // The name is gone from main; dev still holds it, and the bytes survive.
  string.contains(message, "dev") |> should.be_true
  namespace.load_current(adapter, "main")
  |> should.equal(Ok(namespace.empty()))
  namespace.load_current(adapter, "dev")
  |> should.equal(Ok(namespace.set(namespace.empty(), "a", ref)))
  let assert Ok(Some(_)) = adapter.lookup(ref)
  let assert Ok(_) = simplifile.delete(path)
}

/// The same refusal for purge, whose removal set is larger.
pub fn purge_refuses_while_another_branch_binds_it_test() {
  let #(adapter, ref) = seeded()
  let assert Ok(_) =
    namespace.commit(
      adapter,
      "main",
      namespace.set(namespace.empty(), "a", ref),
    )
  let assert Ok(_) =
    namespace.commit(adapter, "dev", namespace.set(namespace.empty(), "a", ref))
  let path = index_file("a", ref)
  case cli_purge.purge(adapter, path, ref, "main", True) {
    Ok(_) -> panic as "purged content another branch still binds"
    Error(#(_, message)) -> {
      string.contains(message, "dev") |> should.be_true
      let assert Ok(Some(_)) = adapter.lookup(ref)
      let assert Ok(_) = simplifile.delete(path)
      Nil
    }
  }
}

/// Once the other branch lets go, the retraction proceeds: the refusal is a
/// state, not a permanent veto.
pub fn unpublish_proceeds_once_no_other_branch_binds_it_test() {
  let #(adapter, ref) = seeded()
  let assert Ok(_) =
    namespace.commit(
      adapter,
      "main",
      namespace.set(namespace.empty(), "a", ref),
    )
  let assert Ok(_) = namespace.commit(adapter, "dev", namespace.empty())
  let path = index_file("a", ref)
  let lines = index_lines("a", ref)
  let assert Ok(message) =
    cli_unpublish.retract(adapter, path, "a", ref_hex(ref), ref, "main", lines)
  string.contains(message, "unpublished") |> should.be_true
  adapter.lookup(ref) |> should.equal(Ok(None))
  let assert Ok(_) = simplifile.delete(path)
}

/// The published index is store-wide; a binding is per-branch. Retracting on
/// one branch removes the index line, so the other branch's binding had no
/// index line left to find and could never be retracted — the name stayed bound
/// forever. The branch namespace is the authority for its own bindings.
pub fn a_branch_binding_survives_losing_the_index_line_test() {
  let #(adapter, ref) = seeded()
  let assert Ok(_) =
    namespace.commit(
      adapter,
      "main",
      namespace.set(namespace.empty(), "a", ref),
    )
  let assert Ok(_) =
    namespace.commit(adapter, "dev", namespace.set(namespace.empty(), "a", ref))
  // The index line is already gone: main retracted it first.
  case cli_unpublish.resolve_target(adapter, [], "a", "dev") {
    Error(_) -> panic as "a bound name was reported unpublished"
    Ok(#(hash, found)) -> {
      hash |> should.equal(ref_hex(ref))
      found |> should.equal(ref)
    }
  }
}

/// A name nobody binds, on a branch with no index line, is still nothing to
/// retract.
pub fn an_unbound_name_is_still_refused_test() {
  let #(adapter, ref) = seeded()
  let assert Ok(_) =
    namespace.commit(adapter, "dev", namespace.set(namespace.empty(), "a", ref))
  case cli_unpublish.resolve_target(adapter, [], "nobody", "dev") {
    Ok(_) -> panic as "retracted a name nobody binds"
    Error(#(code, message)) -> {
      code |> should.equal(cli_result.refused)
      string.contains(message, "not published") |> should.be_true
    }
  }
}
