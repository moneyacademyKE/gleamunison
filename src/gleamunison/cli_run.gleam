//// `gleamunison run <content-hash> [args...] [--store path]` — execute a
//// definition the store already holds. The hash is the identity: there is no
//// name to resolve and no source to paste. `publish` prints the hash this
//// command takes.
////
//// A function is a value: `run <hash> 2 3` applies a two-parameter function
//// one argument at a time. Arguments are Erlang terms (integers, floats,
//// true/false/nil, "quoted text"); anything that does not parse as one is
//// passed as raw text, so `run <hash> hello` reaches a text parameter.
////
//// The store comes from GLEAMUNISON_STORE_DIR (or --store), and the evidence
//// gate is on unless GLEAMUNISON_STORE_ALLOW_UNVERIFIED says otherwise.

import gleam/dynamic.{type Dynamic}
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleamunison/cli_lifecycle
import gleamunison/cli_result
import gleamunison/cli_store
import gleamunison/identity
import gleamunison/run_ref

@external(erlang, "gleamunison_ffi", "parse_term_arg")
fn parse_term_arg(arg: String) -> Result(Dynamic, Nil)

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn text_arg(arg: String) -> Dynamic

pub fn command(args: List(String)) -> Nil {
  case run(args) {
    Ok(value) -> {
      io.println(value)
      Nil
    }
    Error(#(code, message)) -> cli_result.fail_with_code(code, message)
  }
}

/// The exit-code contract: 1 when the run gate refuses (the request was
/// understood and declined), 2 when the target cannot be resolved (absent from
/// the store, unreadable, or a store that disagrees with its own refs). A
/// script can tell "no such definition" from "you called it wrong".
fn run(args: List(String)) -> Result(String, #(Int, String)) {
  case args {
    ["--help"] | ["help"] -> Ok(usage())
    _ -> execute(args)
  }
}

fn execute(args: List(String)) -> Result(String, #(Int, String)) {
  use #(hash, call_args, store_override) <- result.try(
    parse_args(args, None, [], None)
    |> result.map_error(fn(message) { #(cli_result.refused, message) }),
  )
  use ref <- result.try(
    identity.parse_ref_hex(hash)
    |> result.map_error(fn(message) { #(cli_result.unresolvable, message) }),
  )
  use store_path <- result.try(
    resolve_store_path(store_override)
    |> result.map_error(fn(message) { #(cli_result.unresolvable, message) }),
  )
  let allow_unverified = cli_lifecycle.resolve_allow_unverified()
  case allow_unverified {
    True ->
      io.println_error(
        "run: warning — GLEAMUNISON_STORE_ALLOW_UNVERIFIED is set;"
        <> " executing content whose evidence was not checked",
      )
    False -> Nil
  }
  use output <- result.try(
    cli_store.with_dets_mapped(
      store_path,
      fn(adapter) {
        run_ref.run_verified(adapter, ref, call_args, allow_unverified)
        |> result.map_error(classify)
      },
      fn(message) { #(cli_result.unresolvable, message) },
    ),
  )
  Ok(output)
}

/// Refused vs could-not-resolve: the two failures a caller scripts against.
fn classify(error: run_ref.RunError) -> #(Int, String) {
  let message = run_ref.describe(error)
  case error {
    run_ref.Missing(_) -> #(cli_result.unresolvable, message)
    run_ref.Unreadable(_, _) -> #(cli_result.unresolvable, message)
    run_ref.Cycle(_) -> #(cli_result.unresolvable, message)
    run_ref.ArityUnavailable(_, _, _) -> #(cli_result.refused, message)
    run_ref.NoEvidence(_, _) -> #(cli_result.refused, message)
    run_ref.NotExecutable(_, _) -> #(cli_result.refused, message)
    run_ref.LoadFailed(_, _) -> #(cli_result.refused, message)
    run_ref.EvaluationFailed(_, _) -> #(cli_result.refused, message)
  }
}

fn resolve_store_path(override: Option(String)) -> Result(String, String) {
  case override {
    Some(path) -> Ok(path)
    None -> cli_lifecycle.resolve_store_path()
  }
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
  store_override: Option(String),
) -> Result(#(String, List(Dynamic), Option(String)), String) {
  case args {
    [] ->
      case hash {
        Some(value) ->
          Ok(#(value, to_call_args(list.reverse(call_args)), store_override))
        None -> Error(usage())
      }
    ["--store", path, ..rest] -> parse_args(rest, hash, call_args, Some(path))
    ["--store"] -> Error("run: --store needs a path\n" <> usage())
    [value, ..rest] ->
      case hash {
        Some(_) -> parse_args(rest, hash, [value, ..call_args], store_override)
        None -> parse_args(rest, Some(value), call_args, store_override)
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
  <> "\n"
  <> "The store is verified content by default. Set GLEAMUNISON_STORE_DIR to\n"
  <> "use another store directory, and GLEAMUNISON_STORE_ALLOW_UNVERIFIED=1\n"
  <> "to execute content whose evidence does not check out (local work only).\n"
  <> "Default store: "
  <> cli_lifecycle.default_store_dir()
  <> "/store.dets"
}
