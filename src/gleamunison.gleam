import dogfood
import dogfood_meta as meta
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleamunison/http
import gleamunison/repl

pub fn main() -> Nil {
  run(get_plain_args())
}

@external(erlang, "gleamunison_ffi", "get_plain_args")
fn get_plain_args() -> List(String)

pub fn run(args: List(String)) -> Nil {
  let levels = dogfood.all_levels()
  case args {
    [] -> print_help()
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
    _ ->
      case dict.get(levels, cmd) {
        Ok(f) -> f()
        Error(_) ->
          io.println(
            "Unknown command: '"
            <> cmd
            <> "'. Try: server, repl, all, level1..level1000",
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
  io.println("=== All 1250 levels complete ===")
}

fn print_help() -> Nil {
  io.println("Gleamunison — content-addressed language runtime on the BEAM")
  io.println("Usage: gleam run -- <command>")
  io.println("  server [port]   — start web server (default port 8080)")
  io.println("  repl            — interactive REPL")
  io.println("  all             — run all levels (1-1250)")
  io.println("  levelN          — run level N (1-1250)")
}
