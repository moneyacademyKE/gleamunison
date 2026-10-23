//// `gleamunison run <content-hash> [args...] [--store path]` — execute a
//// definition the store already holds. The hash is the identity: there is no
//// name to resolve and no source to paste. `publish` prints the hash this
//// command takes.
////
//// A function is a value: `run <hash> 2 3` applies a two-parameter function
//// one argument at a time. Arguments are Erlang terms (integers, floats,
//// true/false/nil, "quoted text"); anything that does not parse as one is
//// passed as raw text, so `run <hash> hello` reaches a text parameter.

import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleamunison/cli_result
import gleamunison/cli_store
import gleamunison/identity
import gleamunison/run_ref

const default_store = ".gleamunison/store.dets"

@external(erlang, "gleamunison_ffi", "parse_term_arg")
fn parse_term_arg(arg: String) -> Result(Dynamic, Nil)

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn text_arg(arg: String) -> Dynamic

pub fn command(args: List(String)) -> Result(Nil, String) {
  case args {
    ["--help"] | ["help"] -> cli_result.success(usage())
    _ -> run(args)
  }
}

fn run(args: List(String)) -> Result(Nil, String) {
  use #(hash, call_args, store_path) <- result.try(parse_args(
    args,
    None,
    [],
    default_store,
  ))
  use ref <- result.try(identity.parse_ref_hex(hash))
  use output <- result.try(
    cli_store.with_dets(store_path, fn(adapter) {
      run_ref.run(adapter, ref, call_args) |> result.map_error(run_ref.describe)
    }),
  )
  cli_result.success(output)
}

/// Each argument is a term when it parses as one, raw text otherwise. The
/// fallback is deliberate: `hello` is a text argument, `3x` is text too, and
/// the type error at the call site is the honest report.
fn to_call_args(args: List(String)) -> List(Dynamic) {
  list.map(args, fn(arg) {
    case parse_term_arg(arg) {
      Ok(term) -> term
      Error(_) -> text_arg(arg)
    }
  })
}

fn parse_args(
  args: List(String),
  hash: Option(String),
  call_args: List(String),
  store_path: String,
) -> Result(#(String, List(Dynamic), String), String) {
  case args {
    [] ->
      case hash {
        Some(value) ->
          Ok(#(value, to_call_args(list.reverse(call_args)), store_path))
        None -> Error(usage())
      }
    ["--store", path, ..rest] -> parse_args(rest, hash, call_args, path)
    ["--store"] -> Error("run: --store needs a path\n" <> usage())
    [value, ..rest] ->
      case hash {
        Some(_) -> parse_args(rest, hash, [value, ..call_args], store_path)
        None -> parse_args(rest, Some(value), call_args, store_path)
      }
  }
}

fn usage() -> String {
  "usage: gleam run -- run <content-hash> [args...] [--store path]\n"
  <> "\n"
  <> "Runs the definition the store holds under that hash, loading its\n"
  <> "dependencies first. The hash is the content hash printed by publish.\n"
  <> "\n"
  <> "A value takes no arguments. A function of arity N takes N: each is\n"
  <> "read as an Erlang term (42, 1.5, true, nil, \"text\") and passed as raw\n"
  <> "text when it does not parse as one.\n"
  <> "Default store: "
  <> default_store
}
