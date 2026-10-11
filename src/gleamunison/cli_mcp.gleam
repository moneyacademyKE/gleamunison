//// `gleamunison mcp [port] [--load file.lisp ...]` — boot an MCP session
//// (optionally loading definitions from files) and serve the JSON-RPC
//// endpoint at POST /mcp on the shared HTTP stack.

import gleam/int
import gleam/io
import gleam/list
import gleamunison/http
import gleamunison/mcp_server

pub fn command(args: List(String)) -> Nil {
  case parse_args(args, 8099, []) {
    Error(err) -> io.println("mcp: " <> err)
    Ok(#(port, loads)) ->
      case mcp_server.start(loads) {
        Error(err) -> io.println("mcp: session failed to boot: " <> err)
        Ok(Nil) -> {
          io.println(
            "MCP endpoint: http://localhost:" <> int.to_string(port) <> "/mcp",
          )
          http.start_server(port)
        }
      }
  }
}

fn parse_args(
  args: List(String),
  port: Int,
  loads: List(String),
) -> Result(#(Int, List(String)), String) {
  case args {
    [] -> Ok(#(port, list.reverse(loads)))
    ["--load", path, ..rest] -> parse_args(rest, port, [path, ..loads])
    ["--load"] -> Error("--load needs a file path")
    [arg, ..rest] ->
      case int.parse(arg) {
        Ok(p) -> parse_args(rest, p, loads)
        Error(_) -> Error("unknown argument: " <> arg)
      }
  }
}
