//// `gleamunison log [content|exec] [--tail N]` — what the store has seen.
////
//// The logs are written by whoever admits or executes a definition, not by
//// this command: `log` only reads. Both are append-only and durable across
//// restarts because they are dets tables beside the store file, keyed by a
//// monotonic sequence number.

import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import gleamunison/cli_lifecycle
import gleamunison/cli_result
import gleamunison/identity.{short_hash_hex}
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
  use context <- result.try(
    cli_lifecycle.resolve_context(None)
    |> result.map_error(fn(message) { #(cli_result.unresolvable, message) }),
  )
  let dir = cli_lifecycle.root_dir(context)
  case which {
    "content" -> render_content(dir, count)
    "exec" -> render_exec(dir, count)
    "all" -> render_all(dir, count)
    other ->
      Error(#(
        cli_result.refused,
        "log: unknown log '" <> other <> "' (content | exec | all)\n" <> usage(),
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
          <> short_hash_hex(entry.ref_hex)
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
            <> short_hash_hex(entry.ref_hex)
            <> "  "
            <> entry.outcome
            <> "  "
            <> entry.caller
          case entry.reason {
            "" -> base
            reason -> base <> "  (" <> reason <> ")"
          }
        })
        |> string.join("\n"),
      )
  }
}

/// Both logs in one chronological view: an admission and an execution sit in
/// the same list, ordered by when they happened.
fn render_all(dir: String, count: Int) -> Result(String, #(Int, String)) {
  use entries <- result.try(
    store_log.merged_tail(dir, count)
    |> result.map_error(fn(reason) { #(cli_result.unresolvable, reason) }),
  )
  case entries {
    [] -> Ok("log: nothing recorded yet")
    _ ->
      Ok(
        entries
        |> list.map(fn(entry) {
          let base =
            format_iso8601(entry.at)
            <> "  "
            <> pad(entry.kind)
            <> "  "
            <> short_hash_hex(entry.ref_hex)
            <> "  "
            <> entry.label
          case entry.detail {
            "" -> base
            detail -> base <> "  (" <> detail <> ")"
          }
        })
        |> string.join("\n"),
      )
  }
}

/// Column padding so the merged view lines up: "content" and "exec" differ in
/// width, and a ragged list is harder to scan than a fixed one.
fn pad(kind: String) -> String {
  case string.length(kind) {
    7 -> kind
    shorter -> kind <> string.repeat(" ", 7 - shorter)
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
        "content" | "exec" | "all" -> parse_args(rest, value, count)
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
  <> "all      both, in one chronological view\n"
  <> "Default count: "
  <> int.to_string(default_tail)
}
