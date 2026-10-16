//// `gleam run -- fmt <file>`: opinionated surface formatter (roadmap 9.2).
//// Rewrites in place; comments are preserved (see formatter module docs).

import gleam/int
import gleam/io
import gleamunison/formatter
import simplifile

pub fn run(args: List(String)) -> Nil {
  case args {
    [path] -> format_file(path)
    _ -> io.println("usage: gleam run -- fmt <file>  (rewrites in place)")
  }
}

fn format_file(path: String) -> Nil {
  case simplifile.read(path) {
    Error(_) -> io.println("fmt: cannot read " <> path)
    Ok(src) -> {
      case formatter.format_source(src) {
        Error(err) ->
          io.println(
            "fmt: parse error in "
            <> path
            <> " at line "
            <> int.to_string(err.line)
            <> ", col "
            <> int.to_string(err.col)
            <> ": "
            <> err.message,
          )
        Ok(formatted) ->
          case formatted == src {
            True -> io.println("fmt: " <> path <> " unchanged")
            False -> {
              let assert Ok(_) = simplifile.write(path, formatted)
              io.println("fmt: formatted " <> path)
            }
          }
      }
    }
  }
}
