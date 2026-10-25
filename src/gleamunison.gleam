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
import gleamunison/cli_log
import gleamunison/cli_lsp
import gleamunison/cli_mcp
import gleamunison/cli_pkg
import gleamunison/cli_publish
import gleamunison/cli_purge
import gleamunison/cli_replay
import gleamunison/cli_result
import gleamunison/cli_run
import gleamunison/cli_sync
import gleamunison/cli_tape_to_test
import gleamunison/cli_test
import gleamunison/cli_unpublish
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

@external(erlang, "gleamunison_render", "setup_stdio")
fn setup_stdio() -> Nil

@external(erlang, "gleamunison_definition_codec", "version")
fn definition_codec_version() -> Int

pub fn run(args: List(String)) -> Nil {
  // Before any command writes: the console device defaults to latin1, which
  // escapes every codepoint outside Latin-1 as \x{...} — including the em dash
  // in this program's own help text. One call at the entry point, so no command
  // has to remember.
  setup_stdio()
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
    ["run", ..rest] -> cli_run.command(rest)
    ["replay", ..rest] -> cli_result.finish(cli_replay.command(rest))
    ["tape-to-test", ..rest] -> cli_tape_to_test.command(rest)
    ["test", ..rest] -> cli_test.command(rest)
    ["publish", ..rest] -> cli_publish.command(rest)
    ["unpublish", ..rest] -> cli_unpublish.command(rest)
    ["purge", ..rest] -> cli_purge.command(rest)
    ["evidence", ..rest] -> cli_result.finish(cli_evidence.command(rest))
    ["lsp", ..rest] -> cli_lsp.command(rest)
    ["log", ..rest] -> cli_log.command(rest)
    ["sync", ..rest] -> cli_result.finish(cli_sync.command(rest))
    ["pkg", ..rest] -> cli_result.finish_coded(cli_pkg.command(rest))
    ["watch", path] -> cli_watch.command(path)
    ["watch"] -> cli_result.fail("usage: gleam run -- watch <file.lisp>")
    ["repl", ..paths] -> repl.start_repl_loading(paths)
    ["version"] -> io.println(version.current())
    // Storage/schema compatibility gate: upgrade tooling compares this
    // across releases; a bump means stores need an explicit migration.
    ["schema-version"] -> io.println(int.to_string(definition_codec_version()))
    ["--help"] -> print_help()
    ["help"] -> print_help()
    [cmd] -> dispatch(cmd, "8080")
    [cmd, param] -> dispatch(cmd, param)
    [cmd, ..] -> dispatch(cmd, "8080")
  }
}

fn dispatch(cmd: String, param: String) -> Nil {
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
    "all" -> run_all_levels()
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
    _ -> dispatch_level(cmd)
  }
}

/// The level table is only built when a level command needs it. `--help`,
/// `version`, `datalog` and every other command used to pay for 6,696 tuples
/// and a full dict construction before dispatch even looked at argv.
fn levels() -> Result(dict.Dict(String, fn() -> Nil), String) {
  dogfood.all_levels()
}

fn dispatch_level(cmd: String) -> Nil {
  case levels() {
    Ok(table) ->
      case dict.get(table, cmd) {
        Ok(f) -> f()
        Error(_) -> {
          io.println(
            "Unknown command: '" <> cmd <> "'. Run --help for the list.",
          )
          halt_failure()
        }
      }
    Error(e) -> level_data_error(e)
  }
}

fn run_all_levels() -> Nil {
  case levels() {
    Ok(table) -> {
      let keys = dict.keys(table)
      list.each(keys, fn(key) {
        case dict.get(table, key) {
          Ok(f) -> f()
          Error(_) -> Nil
        }
      })
      io.println(
        "=== " <> int.to_string(list.length(keys)) <> " levels complete ===",
      )
    }
    Error(e) -> level_data_error(e)
  }
}

fn level_data_error(message: String) -> Nil {
  io.println("ERROR: " <> message)
  io.println("This build cannot run levels: the level data file is missing.")
  halt_failure()
}

fn print_help() -> Nil {
  io.println("Gleamunison — content-addressed language runtime on the BEAM")
  io.println("Usage: gleamunison <command> [args]")
  io.println("")
  io.println("Runtime")
  io.println("  server [port]          start the web server (default 8080)")
  io.println(
    "  repl [file.lisp ...]   interactive REPL, optionally preloading files",
  )
  io.println("  verify [file]          verify a scratch.lisp file")
  io.println("  run <content-hash>     run a definition from the store by hash")
  io.println("  datalog <file.lisp>    run a datalog program")
  io.println("  fmt <file>             rewrite a file in place")
  io.println("  all                    run every implemented level")
  io.println("  levelN                 run level N")
  io.println("  version                print the runtime version")
  io.println("  schema-version         print the storage/codec schema version")
  io.println("")
  io.println("Definitions and evidence")
  io.println(
    "  publish <file.lisp>    publish a definition behind the evidence gate",
  )
  io.println(
    "  unpublish <name>       retract a name: index line, binding, and bytes",
  )
  io.println(
    "  purge <hash> [--yes]   remove a definition and its exclusive deps",
  )
  io.println("  log [content|exec]     what the store has seen (--tail N)")
  io.println("  evidence <hash>        list attestations for a content hash")
  io.println(
    "  evidence attest <hash> io <note...>   record a human attestation",
  )
  io.println("  test <file.lisp>       run the test forms in a file")
  io.println("  replay <file.lisp> <def> <tape.json>  replay a recorded tape")
  io.println(
    "  tape-to-test <file.lisp> <def> <tape.json>  turn a tape into a test",
  )
  io.println("")
  io.println("Discovery and agents")
  io.println(
    "  find <intent> [--load f] [--limit N]  search definitions by intent",
  )
  io.println("  llm [openai|anthropic] <prompt>       call an LLM")
  io.println("  mcp [port] [--load f]  MCP server for agents (default 8099)")
  io.println("  lsp                    language server on stdio")
  io.println("")
  io.println("Distribution")
  io.println(
    "  sync <host:port> [--store path] [--branch name]  sync with a peer",
  )
  io.println("  pkg install <manifest-hash> [--peer host:port]")
  io.println("  pkg publish <file.lisp> --name <pkg> --version <v>")
  io.println("  watch <file.lisp>      watch a file and re-run it on change")
  io.println("  help, --help, demo     this list")
}
