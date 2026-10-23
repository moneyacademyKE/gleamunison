//// `gleamunison run <content-hash> [--store path]` — execute a definition the
//// store already holds. The hash is the identity: there is no name to resolve
//// and no source to paste. `publish` prints the hash this command takes.

import gleam/option.{type Option, None, Some}
import gleam/result
import gleamunison/cli_result
import gleamunison/cli_store
import gleamunison/identity
import gleamunison/run_ref

const default_store = ".gleamunison/store.dets"

pub fn command(args: List(String)) -> Result(Nil, String) {
  case args {
    ["--help"] | ["help"] -> cli_result.success(usage())
    _ -> run(args)
  }
}

fn run(args: List(String)) -> Result(Nil, String) {
  use #(hash, store_path) <- result.try(parse_args(args, None, default_store))
  use ref <- result.try(identity.parse_ref_hex(hash))
  use output <- result.try(
    cli_store.with_dets(store_path, fn(adapter) {
      run_ref.run(adapter, ref) |> result.map_error(run_ref.describe)
    }),
  )
  cli_result.success(output)
}

fn parse_args(
  args: List(String),
  hash: Option(String),
  store_path: String,
) -> Result(#(String, String), String) {
  case args {
    [] ->
      case hash {
        Some(value) -> Ok(#(value, store_path))
        None -> Error(usage())
      }
    ["--store", path, ..rest] -> parse_args(rest, hash, path)
    ["--store"] -> Error("run: --store needs a path\n" <> usage())
    [value, ..rest] ->
      case hash {
        Some(_) ->
          Error("run: unexpected argument '" <> value <> "'\n" <> usage())
        None -> parse_args(rest, Some(value), store_path)
      }
  }
}

fn usage() -> String {
  "usage: gleam run -- run <content-hash> [--store path]\n"
  <> "\n"
  <> "Runs the definition the store holds under that hash, loading its\n"
  <> "dependencies first. The hash is the content hash printed by publish.\n"
  <> "Default store: "
  <> default_store
}
