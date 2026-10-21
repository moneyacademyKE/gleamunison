import dogfood
import dogfood_meta as meta
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleamunison/cli_datalog
import gleamunison/cli_evidence
import gleamunison/cli_find
import gleamunison/cli_fmt
import gleamunison/cli_llm
import gleamunison/cli_lsp
import gleamunison/cli_mcp
import gleamunison/cli_pkg
import gleamunison/cli_publish
import gleamunison/cli_replay
import gleamunison/cli_result
import gleamunison/cli_sync
import gleamunison/cli_tape_to_test
import gleamunison/cli_test
import gleamunison/cli_watch
import gleamunison/http
import gleamunison/repl
import gleamunison/verify
import gleamunison/version

pub fn main() -> Nil {
  run(get_plain_args())
}

@external(erlang, "gleamunison_ffi", "get_plain_args")
fn get_plain_args() -> List(String)

@external(erlang, "gleamunison_ffi", "halt_failure")
fn halt_failure() -> Nil

@external(erlang, "gleamunison_definition_codec", "version")
fn definition_codec_version() -> Int

pub fn run(args: List(String)) -> Nil {
  let levels = dogfood.all_levels()
  case args {
    [] -> print_help()
    ["llm", ..rest] -> cli_result.print(cli_llm.command_result(rest))
    ["datalog", path] ->
      case cli_datalog.run(path) {
        Ok(out) -> io.println(out)
        Error(err) -> {
          io.println("ERROR: " <> err)
          halt_failure()
        }
      }
    ["datalog"] -> cli_result.fail("usage: gleam run -- datalog <file.lisp>")
    ["mcp", ..rest] -> cli_result.finish(cli_mcp.command(rest))
    ["find", ..rest] -> cli_result.finish(cli_find.command(rest))
    ["fmt", ..rest] -> cli_result.finish(cli_fmt.run(rest))
    ["replay", ..rest] -> cli_result.finish(cli_replay.command(rest))
    ["tape-to-test", ..rest] -> cli_tape_to_test.command(rest)
    ["test", ..rest] -> cli_test.command(rest)
    ["publish", ..rest] -> cli_publish.command(rest)
    ["evidence", ..rest] -> cli_result.finish(cli_evidence.command(rest))
    ["lsp", ..rest] -> cli_lsp.command(rest)
    ["sync", ..rest] -> cli_result.finish(cli_sync.command(rest))
    ["pkg", ..rest] -> cli_result.finish(cli_pkg.command(rest))
    ["watch", path] -> cli_watch.command(path)
    ["watch"] -> cli_result.fail("usage: gleam run -- watch <file.lisp>")
    ["repl", ..paths] -> repl.start_repl_loading(paths)
    ["version"] -> io.println(version.current())
    // Storage/schema compatibility gate: upgrade tooling compares this
    // across releases; a bump means stores need an explicit migration.
    ["schema-version"] -> io.println(int.to_string(definition_codec_version()))
    ["--help"] -> print_help()
    ["help"] -> print_help()
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
    "repl" -> repl.start_repl_loading([])
    "all" -> run_all_levels(levels)
    "level70" -> meta.level70()
    "verify" -> {
      case verify.verify_file(param) {
        Ok(msg) -> io.println("OK: " <> msg)
        Error(err) -> {
          io.println("ERROR: " <> err)
          halt_failure()
        }
      }
    }
    _ ->
      case dict.get(levels, cmd) {
        Ok(f) -> f()
        Error(_) -> {
          io.println(
            "Unknown command: '"
            <> cmd
            <> "'. Try: server, repl, all, verify, level1..level6697",
          )
          halt_failure()
        }
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
  io.println(
    "  repl            — interactive REPL (optional: file.lisp to preload)",
  )
  io.println("  verify [file]   — verify a scratch.lisp file")
  io.println(
    "  llm [provider] <prompt> — call an LLM (openai|anthropic, env keys)",
  )
  io.println(
    "  mcp [port] [--load f] — MCP server for agents (default port 8099)",
  )
  io.println("  all             — run all available levels")
  io.println("  schema-version  — print the storage/codec schema version")
  io.println("  levelN          — run level N")
}
