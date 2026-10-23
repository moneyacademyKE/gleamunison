//// `gleamunison log [content|exec] [--tail N]` — what the store has seen.
////
//// The logs are written by whoever admits or executes a definition, not by
//// this command: `log` only reads. Both are append-only and durable across
//// restarts because they are dets tables beside the store file, keyed by a
//// monotonic sequence number.

import gleam/int
import gleam/io
import gleam/list

import gleam/result
import gleam/string
import gleamunison/cli_lifecycle
import gleamunison/cli_result
import gleamunison/store_log

const default_tail = 20

@external(erlang, "gleamunison_datetime", "format_iso8601")
fn format_iso8601(seconds: Int) -> String

pub fn command(args: List(String)) -> Nil {
  case run(args) {
    Ok(message) -> io.println(message)
    Error(#(code, message)) -> cli_result.fail_with_code(code, message)
  }
}

fn run(args: List(String)) -> Result(String, #(Int, String)) {
  use #(which, count) <- result.try(parse_args(args, "content", default_tail))
  use dir <- result.try(
    cli_lifecycle.resolve_store_dir()
    |> result.map_error(fn(message) { #(cli_result.unresolvable, message) }),
  )
  case which {
    "content" -> render_content(dir, count)
    "exec" -> render_exec(dir, count)
    other ->
      Error(#(
        cli_result.refused,
        "log: unknown log '" <> other <> "' (content | exec)\n" <> usage(),
      ))
  }
}

fn render_content(dir: String, count: Int) -> Result(String, #(Int, String)) {
  use entries <- result.try(
    store_log.content_tail(dir, count)
    |> result.map_error(fn(reason) { #(cli_result.unresolvable, reason) }),
  )
  case entries {
    [] -> Ok("log: no content entries")
    _ ->
      Ok(
        entries
        |> list.map(fn(entry) {
          format_iso8601(entry.at)
          <> "  "
          <> string.slice(entry.ref_hex, 0, 12)
          <> "  "
          <> entry.kind
        })
        |> string.join("\n"),
      )
  }
}

fn render_exec(dir: String, count: Int) -> Result(String, #(Int, String)) {
  use entries <- result.try(
    store_log.exec_tail(dir, count)
    |> result.map_error(fn(reason) { #(cli_result.unresolvable, reason) }),
  )
  case entries {
    [] -> Ok("log: no execution entries")
    _ ->
      Ok(
        entries
        |> list.map(fn(entry) {
          let base =
            format_iso8601(entry.at)
            <> "  "
            <> string.slice(entry.ref_hex, 0, 12)
            <> "  "
            <> entry.outcome
          case entry.reason {
            "" -> base
            reason -> base <> "  (" <> reason <> ")"
          }
        })
        |> string.join("\n"),
      )
  }
}

fn parse_args(
  args: List(String),
  which: String,
  count: Int,
) -> Result(#(String, Int), #(Int, String)) {
  case args {
    [] -> Ok(#(which, count))
    ["--tail", value, ..rest] ->
      case int.parse(value) {
        Ok(n) if n > 0 -> parse_args(rest, which, n)
        _ ->
          Error(#(
            cli_result.refused,
            "log: --tail needs a positive count, got '" <> value <> "'",
          ))
      }
    ["--tail"] ->
      Error(#(cli_result.refused, "log: --tail needs a count\n" <> usage()))
    [value, ..rest] ->
      case value {
        "content" | "exec" -> parse_args(rest, value, count)
        _ ->
          Error(#(
            cli_result.refused,
            "log: unexpected argument '" <> value <> "'\n" <> usage(),
          ))
      }
  }
}

fn usage() -> String {
  "usage: gleam run -- log [content|exec] [--tail N]\n"
  <> "\n"
  <> "content  definitions that entered the store (default)\n"
  <> "exec     execution attempts, with outcome and reason\n"
  <> "Default count: "
  <> int.to_string(default_tail)
}
