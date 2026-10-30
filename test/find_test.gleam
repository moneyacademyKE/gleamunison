import envoy
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleamunison/ast
import gleamunison/cli_find
import gleamunison/codebase
import gleamunison/identity.{Ref, hash_to_debug_string}
import gleamunison/mcp_session
import gleamunison/namespace
import gleamunison/storage
import gleeunit/should
import simplifile
import test_ffi.{without_active_storage}

pub fn find_boots_from_the_selected_durable_branch_test() {
  let dir = "/tmp/gleamunison-find-cli-test"
  let path = dir <> "/store.dets"
  let _ = storage.dets_delete_file(path)
  let assert Ok(_) = simplifile.create_directory_all(dir)
  let assert Ok(adapter) = storage.dets(path)
  let definition = ast.TermDef(ast.Int(42), ast.Builtin(ast.IntType))
  let ref = Ref(codebase.hash_of_definition(definition))
  let assert Ok(_) =
    codebase.insert(
      codebase.with_adapter(adapter),
      ast.Unit(ref, [#(ref, definition)]),
    )
  let assert Ok(_) =
    namespace.commit(
      adapter,
      "factory",
      namespace.set(namespace.empty(), "published-answer", ref),
    )
  let assert Ok(_) = adapter.close()
  envoy.set("GLEAMUNISON_STORE_DIR", dir)
  envoy.set("GLEAMUNISON_BRANCH", "factory")
  let #(state, command_result) =
    without_active_storage(fn() {
      let assert Ok(selected) = mcp_session.boot_configured()
      #(selected, cli_find.command(["published-answer"]))
    })
  command_result |> should.equal(Ok(Nil))
  let assert Ok(hit) =
    list.find(mcp_session.search(state, "published-answer"), fn(hit) {
      hit.name == "published-answer"
    })
  hit.origin |> should.equal("branch")
  hit.branch |> should.equal(Some("factory"))
  let Ref(hash) = ref
  hit.content_ref_hex |> should.equal(Some(hash_to_debug_string(hash)))
  envoy.unset("GLEAMUNISON_STORE_DIR")
  envoy.unset("GLEAMUNISON_BRANCH")
  let assert Ok(_) = storage.dets_delete_file(path)
  let assert Ok(_) = simplifile.delete(dir)
}

pub fn find_bootstrap_definition_by_name_test() {
  let state = mcp_session.boot()
  let hits = mcp_session.search(state, "add")
  let names = list.map(hits, fn(h) { h.name })
  list.contains(names, "add") |> should.be_true
}

pub fn find_ranks_name_matches_first_test() {
  let state = mcp_session.boot()
  let hits = mcp_session.search(state, "add")
  let assert [first, ..] = hits
  first.name |> should.equal("add")
}

pub fn find_hit_carries_kind_and_ref_test() {
  let state = mcp_session.boot()
  let hits = mcp_session.search(state, "add")
  let assert [first, ..] = hits
  first.kind |> should.equal("term")
  { string.length(first.ref_hex) > 0 } |> should.be_true
}

pub fn find_no_match_is_empty_test() {
  let state = mcp_session.boot()
  mcp_session.search(state, "zzz-no-such-def-zzz") |> should.equal([])
}
