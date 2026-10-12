import dogfood
import dogfood_meta as meta
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleamunison/cli_datalog
import gleamunison/cli_evidence
import gleamunison/cli_find
import gleamunison/cli_llm
import gleamunison/cli_lsp
import gleamunison/cli_mcp
import gleamunison/cli_replay
import gleamunison/cli_sync
import gleamunison/cli_test
import gleamunison/cli_watch
import gleamunison/http
import gleamunison/repl
import gleamunison/verify

pub fn main() -> Nil {
  run(get_plain_args())
}

@external(erlang, "gleamunison_ffi", "get_plain_args")
fn get_plain_args() -> List(String)

pub fn run(args: List(String)) -> Nil {
  let levels = dogfood.all_levels()
  case args {
    [] -> print_help()
    ["llm", ..rest] -> io.println(cli_llm.command(rest))
    ["datalog", path] ->
      case cli_datalog.run(path) {
        Ok(out) -> io.println(out)
        Error(err) -> io.println("ERROR: " <> err)
      }
    ["datalog"] -> io.println("usage: gleam run -- datalog <file.lisp>")
    ["mcp", ..rest] -> cli_mcp.command(rest)
    ["find", ..rest] -> cli_find.command(rest)
    ["replay", ..rest] -> cli_replay.command(rest)
    ["test", ..rest] -> cli_test.command(rest)
    ["evidence", ..rest] -> cli_evidence.command(rest)
    ["lsp", ..rest] -> cli_lsp.command(rest)
    ["sync", ..rest] -> cli_sync.command(rest)
    ["watch", path] -> cli_watch.command(path)
    ["watch"] -> io.println("usage: gleam run -- watch <file.lisp>")
    [cmd] -> dispatch(cmd, "8080", levels)
    [cmd, param] -> dispatch(cmd, param, levels)
    [cmd, ..] -> dispatch(cmd, "8080", levels)
  }
}

fn dispatch(
  cmd: String,
  param: String,
  levels: dict.Dict(String, fn() -> Nil),
) -> Nil {
  case cmd {
    "server" -> {
      let port = case int.parse(param) {
        Ok(n) -> n
        Error(_) -> 8080
      }
      http.start_server(port)
    }
    "demo" -> print_help()
    "repl" -> repl.start_repl()
    "all" -> run_all_levels(levels)
    "level70" -> meta.level70()
    "verify" -> {
      case verify.verify_file(param) {
        Ok(msg) -> io.println("OK: " <> msg)
        Error(err) -> io.println("ERROR: " <> err)
      }
    }
    _ ->
      case dict.get(levels, cmd) {
        Ok(f) -> f()
        Error(_) ->
          io.println(
            "Unknown command: '"
            <> cmd
            <> "'. Try: server, repl, all, verify, level1..level6697",
          )
      }
  }
}

fn range(start: Int, end: Int) -> List(Int) {
  case start > end {
    True -> []
    False -> [start, ..range(start + 1, end)]
  }
}

fn run_all_levels(levels: dict.Dict(String, fn() -> Nil)) -> Nil {
  let r = range(1, 6697)
  list.each(r, fn(n) {
    let key = "level" <> int.to_string(n)
    case dict.get(levels, key) {
      Ok(f) -> f()
      Error(_) -> Nil
    }
  })
  io.println("=== All available levels complete ===")
}

fn print_help() -> Nil {
  io.println("Gleamunison — content-addressed language runtime on the BEAM")
  io.println("Usage: gleam run -- <command>")
  io.println("  server [port]   — start web server (default port 8080)")
  io.println("  repl            — interactive REPL")
  io.println("  verify [file]   — verify a scratch.lisp file")
  io.println(
    "  llm [provider] <prompt> — call an LLM (openai|anthropic, env keys)",
  )
  io.println(
    "  mcp [port] [--load f] — MCP server for agents (default port 8099)",
  )
  io.println("  all             — run all available levels")
  io.println("  levelN          — run level N")
}
