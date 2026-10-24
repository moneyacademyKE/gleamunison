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
import gleamunison/cli_output
import gleamunison/cli_result
import gleamunison/cli_store
import gleamunison/identity.{type DefinitionRef}
import gleamunison/run_ref
import gleamunison/storage
import gleamunison/store_log

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
  use #(hash, call_args, store_override, branch_override, json, inspect) <- result.try(
    parse_args(args, None, [], None, None, False, False)
    |> result.map_error(fn(message) { #(cli_result.refused, message) }),
  )
  use ref <- result.try(
    identity.parse_ref_hex(hash)
    |> result.map_error(fn(message) { #(cli_result.unresolvable, message) }),
  )
  use context <- result.try(
    cli_lifecycle.resolve_context(store_override)
    |> result.map_error(fn(message) { #(cli_result.unresolvable, message) }),
  )
  let store_path = cli_lifecycle.store_path(context)
  let branch = case branch_override {
    Some(value) -> value
    None -> "main"
  }
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
        render_output(
          adapter,
          cli_lifecycle.root_dir(context),
          ref,
          branch,
          call_args,
          allow_unverified,
          json,
          inspect,
        )
      },
      fn(message) { #(cli_result.unresolvable, message) },
    ),
  )
  Ok(output)
}

/// Text or JSON, from one execution path. `--inspect` is the only mode that
/// does not execute: it loads the module (dependencies first) to read the
/// export table but never applies `'$eval'`. `--json` always executes and
/// changes only how the result is rendered, so one flag cannot mean two
/// things.
fn render_output(
  adapter: storage.StorageAdapter,
  dir: String,
  ref: DefinitionRef,
  branch: String,
  call_args: List(Dynamic),
  allow_unverified: Bool,
  json: Bool,
  inspect: Bool,
) -> Result(String, #(Int, String)) {
  case inspect {
    True ->
      run_ref.inspect_function_on_branch(adapter, ref, branch)
      |> result.map(fn(info) {
        cli_output.function_json(
          run_ref.hex(ref),
          info.module,
          info.arity,
          info.exports,
        )
      })
      |> result.map_error(classify)
    False ->
      case json {
        False -> {
          let outcome =
            run_ref.run_verified_on_branch(
              adapter,
              ref,
              branch,
              call_args,
              allow_unverified,
            )
          record(dir, ref, outcome)
          outcome |> result.map_error(classify)
        }
        True -> {
          let outcome =
            run_ref.run_verified_raw_on_branch(
              adapter,
              ref,
              branch,
              call_args,
              allow_unverified,
            )
          record(dir, ref, outcome)
          outcome
          |> result.map(fn(term) {
            cli_output.value_json(run_ref.hex(ref), term)
          })
          |> result.map_error(classify)
        }
      }
  }
}

/// Best-effort log write. The log records the run; it is not a precondition for
/// it, so a store that cannot append still executes what it holds — the failure
/// goes to stderr rather than swallowing the result.
fn record(
  dir: String,
  ref: DefinitionRef,
  outcome: Result(a, run_ref.RunError),
) -> Nil {
  let #(kind, reason) = case outcome {
    Ok(_) -> #("ok", "")
    Error(error) -> #("refused", run_ref.describe(error))
  }
  case store_log.record_exec(dir, run_ref.hex(ref), kind, reason, "cli") {
    Ok(_) -> Nil
    Error(problem) ->
      io.println_error("run: cannot write the exec log: " <> problem)
  }
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
  branch: Option(String),
  json: Bool,
  inspect: Bool,
) -> Result(
  #(String, List(Dynamic), Option(String), Option(String), Bool, Bool),
  String,
) {
  case args {
    [] ->
      case hash {
        Some(value) ->
          Ok(#(
            value,
            to_call_args(list.reverse(call_args)),
            store_override,
            branch,
            json,
            inspect,
          ))
        None -> Error(usage())
      }
    ["--json", ..rest] ->
      parse_args(rest, hash, call_args, store_override, branch, True, inspect)
    ["--inspect", ..rest] ->
      parse_args(rest, hash, call_args, store_override, branch, json, True)
    ["--store", path, ..rest] ->
      parse_args(rest, hash, call_args, Some(path), branch, json, inspect)
    ["--store"] -> Error("run: --store needs a path\n" <> usage())
    ["--branch", name, ..rest] ->
      parse_args(
        rest,
        hash,
        call_args,
        store_override,
        Some(name),
        json,
        inspect,
      )
    ["--branch"] -> Error("run: --branch needs a name\n" <> usage())
    [value, ..rest] ->
      case hash {
        Some(_) ->
          parse_args(
            rest,
            hash,
            [value, ..call_args],
            store_override,
            branch,
            json,
            inspect,
          )
        None ->
          parse_args(
            rest,
            Some(value),
            call_args,
            store_override,
            branch,
            json,
            inspect,
          )
      }
  }
}

fn usage() -> String {
  "usage: gleam run -- run <content-hash> [args...] [--json] [--inspect] [--store path] [--branch name]\n"
  <> "\n"
  <> "Runs the definition the store holds under that hash, loading its\n"
  <> "dependencies first. The hash is the content hash printed by publish.\n"
  <> "The branch defaults to main; --branch selects another namespace.\n"
  <> "\n"
  <> "A value takes no arguments. A function of arity N takes N: each is\n"
  <> "read as an Erlang term (42, 1.5, true, nil, \"text\") and passed as raw\n"
  <> "text when it does not parse as one.\n"
  <> "\n"
  <> "  --json     execute, and print the result as one JSON object\n"
  <> "  --inspect  report the module, declared arity and export table WITHOUT\n"
  <> "             calling it; this is the only mode that does not execute\n"
  <> "\n"
  <> "The store is verified content by default. Set GLEAMUNISON_STORE_DIR to\n"
  <> "use another store directory, and GLEAMUNISON_STORE_ALLOW_UNVERIFIED=1\n"
  <> "to execute content whose evidence does not check out (local work only).\n"
  <> "Default store: "
  <> cli_lifecycle.default_store_dir()
  <> "/store.dets"
}
