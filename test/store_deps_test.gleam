//// Retraction: a name is three facts (index line, namespace binding, bytes)
//// and unpublishing removes all three, or refuses and changes none.
////
//// These tests exercise the pieces the command is built from — the dependency
//// scan and the index parsing — on an in-memory store. The command's own exit
//// codes are covered end-to-end in docs/verification/run-identity-proofs.md.

import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleamunison/ast
import gleamunison/cli_store
import gleamunison/codebase
import gleamunison/definition_refs
import gleamunison/dependency_snapshot.{
  CorruptDefinition, NamespaceFailure, StoreFailure, describe_error,
}
import gleamunison/genesis
import gleamunison/identity.{type DefinitionRef, Local, Ref, ref_hex}
import gleamunison/namespace
import gleamunison/repl_eval
import gleamunison/storage
import gleeunit/should
import simplifile

fn insert(
  cb: codebase.Codebase,
  definition: ast.Definition,
) -> #(codebase.Codebase, DefinitionRef) {
  let ref = Ref(codebase.hash_of_definition(definition))
  let assert Ok(cb) =
    codebase.insert(cb, ast.Unit(root: ref, defs: [#(ref, definition)]))
  #(cb, ref)
}

fn int_fn_returning(value: Int) -> ast.Definition {
  ast.TermDef(
    term: ast.Lambda(binder: Local(0), body: ast.Int(value)),
    typ: ast.Fn(
      params: [ast.Builtin(ast.IntType)],
      result: ast.Builtin(ast.IntType),
      requires: ast.Required([]),
    ),
  )
}

pub fn a_definition_with_no_users_has_no_dependents_test() {
  let #(cb, ref) = insert(codebase.empty(), int_fn_returning(1))
  let assert Ok(snapshot) =
    dependency_snapshot.read(codebase.get_adapter(cb), "main")
  dependency_snapshot.dependents(snapshot, ref) |> should.equal([])
}

pub fn a_content_ref_dependent_is_found_test() {
  let #(cb, dep_ref) = insert(codebase.empty(), int_fn_returning(2))
  let caller =
    ast.TermDef(
      term: ast.Apply(function: ast.RefTo(dep_ref), arg: ast.Int(0)),
      typ: ast.Builtin(ast.IntType),
    )
  let #(cb, caller_ref) = insert(cb, caller)
  let assert Ok(snapshot) =
    dependency_snapshot.read(codebase.get_adapter(cb), "main")
  dependency_snapshot.dependents(snapshot, dep_ref)
  |> should.equal([caller_ref])
}

pub fn a_name_ref_dependent_is_found_test() {
  // Elaborated terms reference dependencies by sha256(name). A scan that only
  // matched content refs would report no dependents here, and unpublish would
  // happily delete content another definition still calls.
  let #(cb, dep_ref) = insert(codebase.empty(), int_fn_returning(3))
  let name_ref = repl_eval.ref_for_name("named-dep")
  let caller =
    ast.TermDef(
      term: ast.Apply(function: ast.RefTo(name_ref), arg: ast.Int(0)),
      typ: ast.Builtin(ast.IntType),
    )
  let #(cb, caller_ref) = insert(cb, caller)
  let adapter = codebase.get_adapter(cb)
  let assert Ok(_) =
    namespace.commit(
      adapter,
      "main",
      namespace.set(namespace.empty(), "named-dep", dep_ref),
    )
  let assert Ok(snapshot) = dependency_snapshot.read(adapter, "main")
  dependency_snapshot.dependents(snapshot, dep_ref)
  |> should.equal([caller_ref])
}

pub fn a_name_ref_dependent_is_found_on_the_selected_branch_test() {
  let #(cb, dep_ref) = insert(codebase.empty(), int_fn_returning(13))
  let name_ref = repl_eval.ref_for_name("release-dep")
  let caller =
    ast.TermDef(
      term: ast.Apply(function: ast.RefTo(name_ref), arg: ast.Int(0)),
      typ: ast.Builtin(ast.IntType),
    )
  let #(cb, caller_ref) = insert(cb, caller)
  let adapter = codebase.get_adapter(cb)
  let assert Ok(_) =
    namespace.commit(
      adapter,
      "release",
      namespace.set(namespace.empty(), "release-dep", dep_ref),
    )
  let assert Ok(release) = dependency_snapshot.read(adapter, "release")
  dependency_snapshot.dependents(release, dep_ref)
  |> should.equal([caller_ref])
  let assert Ok(main) = dependency_snapshot.read(adapter, "main")
  dependency_snapshot.dependents(main, dep_ref) |> should.equal([])
}

pub fn the_ref_itself_is_not_its_own_dependent_test() {
  let #(cb, ref) = insert(codebase.empty(), int_fn_returning(4))
  let assert Ok(snapshot) =
    dependency_snapshot.read(codebase.get_adapter(cb), "main")
  dependency_snapshot.dependents(snapshot, ref) |> should.equal([])
}

pub fn another_name_binding_the_same_content_is_reported_test() {
  let #(cb, ref) = insert(codebase.empty(), int_fn_returning(5))
  let adapter = codebase.get_adapter(cb)
  let ns =
    namespace.empty()
    |> namespace.set("first", ref)
    |> namespace.set("second", ref)
  let assert Ok(_) = namespace.commit(adapter, "main", ns)
  // Production's shape (cli_unpublish): one snapshot, then names minus the
  // name being retracted.
  let assert Ok(snapshot) = dependency_snapshot.read(adapter, "main")
  dependency_snapshot.names(snapshot, ref)
  |> list.filter(fn(name) { name != "first" })
  |> should.equal(["second"])
}

pub fn the_only_name_binding_the_content_is_not_another_test() {
  let #(cb, ref) = insert(codebase.empty(), int_fn_returning(6))
  let adapter = codebase.get_adapter(cb)
  let assert Ok(_) =
    namespace.commit(
      adapter,
      "main",
      namespace.set(namespace.empty(), "only", ref),
    )
  let assert Ok(snapshot) = dependency_snapshot.read(adapter, "main")
  dependency_snapshot.names(snapshot, ref)
  |> list.filter(fn(name) { name != "only" })
  |> should.equal([])
}

pub fn a_store_delete_removes_the_binding_test() {
  let #(cb, ref) = insert(codebase.empty(), int_fn_returning(7))
  let adapter = codebase.get_adapter(cb)
  let assert Ok(Some(_)) = adapter.lookup(ref)
  let assert Ok(Nil) = adapter.delete(ref)
  adapter.lookup(ref) |> should.equal(Ok(None))
  codebase.get(cb, ref) |> should.equal(Error(codebase.NotFound(ref)))
}

pub fn a_caller_of_a_genesis_builtin_is_its_dependent_test() {
  // A stored definition that calls `+` references the builtin by its content
  // ref, so it IS a dependent of that ref even though the builtin itself is
  // never stored. Retraction must see it; nothing may delete a builtin, and
  // the scan reporting it keeps that honest.
  let caller =
    ast.TermDef(
      term: ast.Apply(
        function: ast.RefTo(genesis.builtin_int_add()),
        arg: ast.Int(1),
      ),
      typ: ast.Builtin(ast.IntType),
    )
  let #(cb, caller_ref) = insert(codebase.empty(), caller)
  let assert Ok(snapshot) =
    dependency_snapshot.read(codebase.get_adapter(cb), "main")
  dependency_snapshot.dependents(snapshot, genesis.builtin_int_add())
  |> should.equal([caller_ref])
}

pub fn the_definition_refs_walker_agrees_with_the_scan_test() {
  // Sanity: the scan uses refs_of_definition, so a definition that references
  // nothing has no dependents by construction.
  let definition = int_fn_returning(8)
  definition_refs.refs_of_definition(definition) |> should.equal([])
}

pub fn the_closure_is_just_the_root_when_nothing_is_exclusive_test() {
  let #(cb, dep_ref) = insert(codebase.empty(), int_fn_returning(10))
  // Two callers share the dependency: neither purging it nor purging one
  // caller may take it.
  // Two DISTINCT callers: identical definitions hash to one ref, so a
  // duplicate would not be a second dependent at all.
  let caller = fn(n: Int) {
    ast.TermDef(
      term: ast.Apply(function: ast.RefTo(dep_ref), arg: ast.Int(n)),
      typ: ast.Builtin(ast.IntType),
    )
  }
  let #(cb, first) = insert(cb, caller(0))
  let #(cb, _second) = insert(cb, caller(1))
  let assert Ok(snapshot) =
    dependency_snapshot.read(codebase.get_adapter(cb), "main")
  dependency_snapshot.exclusive_closure(snapshot, first)
  |> should.equal([first])
}

pub fn an_exclusive_dependency_joins_the_closure_test() {
  let #(cb, dep_ref) = insert(codebase.empty(), int_fn_returning(11))
  let caller =
    ast.TermDef(
      term: ast.Apply(function: ast.RefTo(dep_ref), arg: ast.Int(0)),
      typ: ast.Builtin(ast.IntType),
    )
  let #(cb, caller_ref) = insert(cb, caller)
  let assert Ok(snapshot) =
    dependency_snapshot.read(codebase.get_adapter(cb), "main")
  dependency_snapshot.exclusive_closure(snapshot, caller_ref)
  |> should.equal([caller_ref, dep_ref])
}

pub fn a_shared_transitive_dependency_stays_test() {
  // root -> mid -> base, and another definition also uses base.
  let #(cb, base_ref) = insert(codebase.empty(), int_fn_returning(12))
  let mid =
    ast.TermDef(
      term: ast.Apply(function: ast.RefTo(base_ref), arg: ast.Int(0)),
      typ: ast.Builtin(ast.IntType),
    )
  let #(cb, mid_ref) = insert(cb, mid)
  let root =
    ast.TermDef(
      term: ast.Apply(function: ast.RefTo(mid_ref), arg: ast.Int(0)),
      typ: ast.Builtin(ast.IntType),
    )
  let #(cb, root_ref) = insert(cb, root)
  let other =
    ast.TermDef(
      term: ast.Apply(function: ast.RefTo(base_ref), arg: ast.Int(1)),
      typ: ast.Builtin(ast.IntType),
    )
  let #(cb, _other_ref) = insert(cb, other)
  let assert Ok(snapshot) =
    dependency_snapshot.read(codebase.get_adapter(cb), "main")
  let closure = dependency_snapshot.exclusive_closure(snapshot, root_ref)
  closure |> should.equal([root_ref, mid_ref])
  closure |> should_not_contain(base_ref)
}

fn should_not_contain(items: List(a), value: a) -> Bool {
  let assert False = list.contains(items, value)
  True
}

pub fn describe_error_store_failure_renders_sentence_test() {
  describe_error(StoreFailure(storage.StorageError("read denied")))
  |> should.equal("read denied")
  describe_error(StoreFailure(storage.NotFound)) |> should.equal("not found")
  describe_error(StoreFailure(storage.IoError("disk offline")))
  |> should.equal("io error: disk offline")
}

pub fn describe_error_namespace_failure_passes_through_test() {
  describe_error(NamespaceFailure("branch pointer unreadable"))
  |> should.equal("branch pointer unreadable")
}

pub fn describe_error_corrupt_definition_names_ref_test() {
  let ref = int_fn_returning(12) |> codebase.hash_of_definition |> Ref
  describe_error(CorruptDefinition(ref))
  |> should.equal("corrupt or unreadable definition " <> ref_hex(ref))
}

pub fn broken_store_path_yields_sentence_not_constructor_dump_test() {
  let dir = "/tmp/gleamunison-store-deps-describe"
  let _ = simplifile.create_directory_all(dir)
  let outcome =
    cli_store.with_dets_mapped(dir, fn(_adapter) { Ok(Nil) }, fn(message) {
      message
    })
  let _ = simplifile.delete(dir)
  let assert Error(message) = outcome
  message
  |> string.starts_with("cannot open store at " <> dir <> ": ")
  |> should.be_true
  message |> string.contains("StorageError(") |> should.be_false
  message |> string.contains("IoError(") |> should.be_false
}
