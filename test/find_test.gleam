import gleam/list
import gleam/string
import gleamunison/mcp_session
import gleeunit/should

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
