import gleam/dict
import gleam/int
import gleam/io
import gleamunison/http
import gleamunison/repl
import dogfood

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

fn dispatch(cmd: String, param: String, levels: dict.Dict(String, fn() -> Nil)) -> Nil {
  case cmd {
    "server" -> {
      let port = case int.parse(param) { Ok(n) -> n Error(_) -> 8080 }
      http.start_server(port)
    }
    "demo" -> print_help()
    "repl" -> repl.start_repl()
    _ -> case dict.get(levels, cmd) {
      Ok(f) -> f()
      Error(_) -> io.println("Unknown command: '" <> cmd <> "'. Try: server, repl, level21..level1000")
    }
  }
}

fn print_help() -> Nil {
  io.println("Gleamunison — content-addressed language runtime on the BEAM")
  io.println("Usage: gleam run -- <command>")
  io.println("  server [port]   — start web server (default port 8080)")
  io.println("  repl            — interactive REPL")
  io.println("  levelN          — run level N (21-1000)")
}
