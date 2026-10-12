//// `gleamunison find <intent> [--load file.lisp ...] [--limit N]` —
//// search the codebase by intent: describe what you want, get the names,
//// kinds and content hashes of definitions that already do it. The hash
//// is the dependency: reference it instead of writing a new function.

import gleam/int
import gleam/io
import gleam/list
import gleam/string
import gleamunison/mcp_session

pub fn command(args: List(String)) -> Nil {
  case parse_args(args, [], [], 10) {
    Error(err) -> io.println("find: " <> err)
    Ok(#(query, loads, limit)) ->
      case query {
        "" ->
          io.println(
            "usage: gleam run -- find <intent> [--load file.lisp ...] [--limit N]",
          )
        _ -> run(query, loads, limit)
      }
  }
}

fn parse_args(
  args: List(String),
  query_parts: List(String),
  loads: List(String),
  limit: Int,
) -> Result(#(String, List(String), Int), String) {
  case args {
    [] ->
      Ok(#(
        list.reverse(query_parts) |> string.join(" "),
        list.reverse(loads),
        limit,
      ))
    ["--load", path, ..rest] ->
      parse_args(rest, query_parts, [path, ..loads], limit)
    ["--load"] -> Error("--load needs a file path")
    ["--limit", n, ..rest] ->
      case int.parse(n) {
        Ok(l) -> parse_args(rest, query_parts, loads, l)
        Error(_) -> Error("--limit needs a number")
      }
    ["--limit"] -> Error("--limit needs a number")
    [word, ..rest] -> parse_args(rest, [word, ..query_parts], loads, limit)
  }
}

fn run(query: String, loads: List(String), limit: Int) -> Nil {
  let state = mcp_session.boot()
  case load_all(state, loads) {
    Error(err) -> io.println("find: " <> err)
    Ok(loaded) -> {
      let hits = mcp_session.search(loaded, query)
      case list.is_empty(hits) {
        True -> io.println("no definitions match: " <> query)
        False ->
          hits
          |> list.take(limit)
          |> list.each(fn(h) {
            io.println(
              h.name
              <> "  :  "
              <> h.kind
              <> "  #"
              <> string.slice(h.ref_hex, 0, 12),
            )
          })
      }
    }
  }
}

fn load_all(
  state: mcp_session.SessionState,
  loads: List(String),
) -> Result(mcp_session.SessionState, String) {
  list.try_fold(loads, state, fn(s, path) { mcp_session.load_file(s, path) })
}
