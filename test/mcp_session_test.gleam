import gleam/list
import gleam/string
import gleamunison/mcp
import gleamunison/mcp_session
import gleamunison/version
import gleeunit/should
import simplifile

pub fn boot_lists_bootstrap_definitions_test() {
  let state = mcp_session.boot()
  let body =
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"list_definitions\",\"arguments\":{}}}"
  let assert mcp.Respond(resp) = mcp_session.handle_rpc(state, body)
  let assert True = string.contains(resp, "\\\"name\\\":\\\"add\\\"")
  let assert True = string.contains(resp, "\\\"name\\\":\\\"Console\\\"")
  let assert True = string.contains(resp, "\\\"kind\\\":\\\"ability\\\"")
}

pub fn load_file_extends_session_test() {
  let path = "/tmp/mcp_session_load_test.lisp"
  let assert Ok(Nil) = simplifile.write(path, "(define mcp-forty-two 42)\n")
  let assert Ok(state) = mcp_session.load_file(mcp_session.boot(), path)
  let body =
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"get_definition\",\"arguments\":{\"name\":\"mcp-forty-two\"}}}"
  let assert mcp.Respond(resp) = mcp_session.handle_rpc(state, body)
  let assert True = string.contains(resp, "mcp-forty-two")
  let assert True = string.contains(resp, "\\\"kind\\\":\\\"term\\\"")
  let assert True = string.contains(resp, "\"isError\":false")
  simplifile.delete(path)
}

pub fn get_definition_unknown_is_error_test() {
  let state = mcp_session.boot()
  let body =
    "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"get_definition\",\"arguments\":{\"name\":\"no-such-def\"}}}"
  let assert mcp.Respond(resp) = mcp_session.handle_rpc(state, body)
  let assert True = string.contains(resp, "\"isError\":true")
}

pub fn search_definitions_matches_substring_test() {
  let path = "/tmp/mcp_session_search_test.lisp"
  let assert Ok(Nil) = simplifile.write(path, "(define mcp-xyzzy-plugh 1)\n")
  let assert Ok(state) = mcp_session.load_file(mcp_session.boot(), path)
  let body =
    "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"search_definitions\",\"arguments\":{\"query\":\"xyzzy\"}}}"
  let assert mcp.Respond(resp) = mcp_session.handle_rpc(state, body)
  let assert True = string.contains(resp, "mcp-xyzzy-plugh")
  simplifile.delete(path)
}

pub fn eval_tool_evaluates_expression_test() {
  let state = mcp_session.boot()
  let body =
    "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"eval\",\"arguments\":{\"expr\":\"(add 1 2)\"}}}"
  let assert mcp.Respond(resp) = mcp_session.handle_rpc(state, body)
  let assert True = string.contains(resp, "\"isError\":false")
  let assert True = string.contains(resp, "3")
}

pub fn eval_tool_rejects_define_test() {
  let state = mcp_session.boot()
  let body =
    "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\",\"params\":{\"name\":\"eval\",\"arguments\":{\"expr\":\"(define sneaky 1)\"}}}"
  let assert mcp.Respond(resp) = mcp_session.handle_rpc(state, body)
  let assert True = string.contains(resp, "\"isError\":true")
}

pub fn tools_list_offers_four_tools_test() {
  let state = mcp_session.boot()
  let body = "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/list\"}"
  let assert mcp.Respond(resp) = mcp_session.handle_rpc(state, body)
  let assert True = string.contains(resp, "list_definitions")
  let assert True = string.contains(resp, "get_definition")
  let assert True = string.contains(resp, "search_definitions")
  let assert True = string.contains(resp, "\"eval\"")
}

// Regression: the search corpus must be the program's own words, never
// debug serialization — inspect(ref) renders internals like Hash(...),
// which made every bootstrap def match the query "hash".
pub fn search_does_not_match_ref_internals_test() {
  let state = mcp_session.boot()
  let hits = mcp_session.search(state, "hash")
  let names = list.map(hits, fn(h) { h.name })
  assert !list.contains(names, "+")
  assert !list.contains(names, "fst")
}

pub fn mcp_version_matches_package_test() {
  let body =
    "{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"initialize\",\"params\":{}}"
  let assert mcp.Respond(resp) =
    mcp_session.handle_rpc(mcp_session.boot(), body)
  string.contains(resp, "\"version\":\"" <> version.current() <> "\"")
  |> should.be_true
}
