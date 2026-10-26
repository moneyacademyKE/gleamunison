import gleam/list
import gleam/option.{Some}
import gleam/string
import gleamunison/agent_publish
import gleamunison/identity
import gleamunison/mcp
import gleamunison/mcp_session
import gleamunison/namespace
import gleamunison/run_ref
import gleamunison/storage
import gleeunit/should
import simplifile

@external(erlang, "gleamunison_ffi_test", "set_env")
fn set_env(key: String, value: String) -> Nil

@external(erlang, "gleamunison_ffi_test", "unset_env")
fn unset_env(key: String) -> Nil

@external(erlang, "gleamunison_ffi_test", "without_active_storage")
fn without_active_storage(check: fn() -> a) -> a

pub fn untested_source_is_refused_before_publication_test() {
  with_store(fn(adapter, _) {
    let source = "(define agent-untested 99)\n"
    let result =
      agent_publish.publish_source(
        adapter,
        source,
        "factory",
        False,
        "/tmp/gleamunison-agent-publish-test",
      )
    result |> should.be_error
    let assert Ok(state) = mcp_session.from_store(adapter, "factory")
    mcp_session.defined_names(state)
    |> list.contains("agent-untested")
    |> should.be_false
  })
}

pub fn tested_source_binds_selected_branch_and_runs_test() {
  with_store(fn(adapter, root) {
    set_env("GLEAMUNISON_EVIDENCE_SIGNING_KEY", "agent-test-key")
    let source =
      "(define agent-answer 42)\n(define test_agent-answer (do Test expect 1))\n"
    let result =
      agent_publish.publish_source(adapter, source, "factory", False, root)
    let assert Ok(publication) = result
    publication.branch |> should.equal("factory")
    publication.admitted |> should.equal(1)
    let assert Ok(published) = list.first(publication.definitions)
    published.name |> should.equal("agent-answer")
    let assert Ok(ref) = identity.parse_ref_hex(published.content_ref)

    let assert Ok(ns) = namespace.load_current(adapter, "factory")
    namespace.get(ns, "agent-answer") |> should.equal(Ok(ref))
    let assert Ok(state) = mcp_session.from_store(adapter, "factory")
    let assert Ok(hit) =
      list.find(mcp_session.search(state, "agent-answer"), fn(hit) {
        hit.name == "agent-answer"
      })
    hit.content_ref_hex |> should.equal(Some(published.content_ref))
    hit.origin |> should.equal("branch")
    run_ref.run_verified_on_branch(adapter, ref, "factory", [], False)
    |> should.equal(Ok("42"))
    unset_env("GLEAMUNISON_EVIDENCE_SIGNING_KEY")
    simplifile.is_file(root <> "/application.dets")
    |> should.equal(Ok(False))
  })
}

pub fn refresh_preserves_scratch_without_stale_stored_types_test() {
  with_store(fn(adapter, root) {
    set_env("GLEAMUNISON_EVIDENCE_SIGNING_KEY", "agent-test-key")
    let initial =
      "(define changing 1)\n(define test_changing (do Test expect 1))\n"
    let updated =
      "(define changing \"new\")\n(define test_changing (do Test expect 1))\n"
    let assert Ok(_) =
      agent_publish.publish_source(adapter, initial, "factory", False, root)
    let assert Ok(previous) = mcp_session.from_store(adapter, "factory")
    let assert Ok(#(_, previous)) =
      mcp_session.define_source(previous, "unrelated-scratch", "7")
    let assert Ok(_) =
      agent_publish.publish_source(adapter, updated, "factory", False, root)
    let assert Ok(fresh) = mcp_session.from_store(adapter, "factory")
    let refreshed = mcp_session.overlay_scratch(fresh, previous)
    let changing =
      mcp_session.handle_rpc(
        refreshed,
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"eval\",\"arguments\":{\"expr\":\"changing\"}}}",
      )
    let scratch =
      mcp_session.handle_rpc(
        refreshed,
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"eval\",\"arguments\":{\"expr\":\"unrelated-scratch\"}}}",
      )
    unset_env("GLEAMUNISON_EVIDENCE_SIGNING_KEY")
    let assert mcp.Respond(changing_body) = changing
    string.contains(changing_body, ": Text") |> should.be_true
    string.contains(changing_body, ": Int") |> should.be_false
    string.contains(changing_body, "new") |> should.be_true
    let assert mcp.Respond(scratch_body) = scratch
    string.contains(scratch_body, "7 : Int") |> should.be_true
  })
}

pub fn untrusted_profile_refuses_agent_writes_test() {
  with_store(fn(adapter, _) {
    let result =
      agent_publish.publish_source(
        adapter,
        "(define nope 1)\n",
        "main",
        True,
        "/tmp/gleamunison-agent-publish-test",
      )
    result |> should.be_error
    let assert Error(message) = result
    string.contains(message, "untrusted") |> should.be_true
  })
}

fn with_store(work: fn(storage.StorageAdapter, String) -> a) -> a {
  let root = "/tmp/gleamunison-agent-publish-test"
  let path = root <> "/store.dets"
  let _ = storage.dets_delete_file(path)
  let assert Ok(_) = simplifile.create_directory_all(root)
  let result =
    without_active_storage(fn() {
      let assert Ok(adapter) = storage.dets(path)
      let value = work(adapter, root)
      value
    })
  let _ = storage.dets_delete_file(path)
  result
}
