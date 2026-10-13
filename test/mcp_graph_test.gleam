import gleam/list
import gleam/string
import gleamunison/mcp
import gleamunison/mcp_session
import gleeunit/should
import simplifile

fn test_state() -> mcp_session.SessionState {
  let path = "/tmp/mcp_graph_test.lisp"
  let src =
    "
(define one 1)
(define inc (lam x (add x one)))
(define inc2 (lam y (inc y)))
"
  let assert Ok(Nil) = simplifile.write(path, src)
  let assert Ok(state) = mcp_session.load_file(mcp_session.boot(), path)
  let _ = simplifile.delete(path)
  state
}

/// callers_of answers "who references this name?" from the datalog index.
pub fn callers_of_finds_referrers_test() {
  let state = test_state()
  let assert Ok(names) = mcp_session.callers_of(state, "one")
  list.contains(names, "inc") |> should.be_true
}

/// deps_of answers "what does this definition reference?" (in-corpus only).
pub fn deps_of_lists_in_corpus_refs_test() {
  let state = test_state()
  let assert Ok(names) = mcp_session.deps_of(state, "inc2")
  list.contains(names, "inc") |> should.be_true
}

/// defs_by_kind filters the index by kind.
pub fn defs_by_kind_terms_test() {
  let state = test_state()
  let assert Ok(names) = mcp_session.defs_by_kind(state, "term")
  list.contains(names, "inc") |> should.be_true
}

/// Unknown name: empty result, not an error.
pub fn callers_of_unknown_is_empty_test() {
  let state = test_state()
  let assert Ok(names) = mcp_session.callers_of(state, "nope-no-such-def")
  names |> should.equal([])
}

/// The MCP tool surface exposes the graph tools.
pub fn graph_tools_registered_test() {
  let state = test_state()
  let body =
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"callers_of\",\"arguments\":{\"name\":\"one\"}}}"
  let resp = mcp_session.handle_rpc(state, body)
  case resp {
    mcp.Respond(content) -> string.contains(content, "inc") |> should.be_true
    mcp.NoReply -> should.fail()
  }
}
