//// `gleam run -- fmt <file>`: opinionated surface formatter (roadmap 9.2).
//// Rewrites in place; comments are preserved (see formatter module docs).

import gleam/int
import gleamunison/cli_result
import gleamunison/formatter
import simplifile

pub fn run(args: List(String)) -> Result(Nil, String) {
  case args {
    [path] -> format_file(path)
    _ -> Error("usage: gleam run -- fmt <file>  (rewrites in place)")
  }
}

fn format_file(path: String) -> Result(Nil, String) {
  case simplifile.read(path) {
    Error(_) -> Error("fmt: cannot read " <> path)
    Ok(src) -> {
      case formatter.format_source(src) {
        Error(err) ->
          Error(
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
            True -> cli_result.success("fmt: " <> path <> " unchanged")
            False ->
              case simplifile.write(path, formatted) {
                Error(_) -> Error("fmt: cannot write " <> path)
                Ok(_) -> cli_result.success("fmt: formatted " <> path)
              }
          }
      }
    }
  }
}
