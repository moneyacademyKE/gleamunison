//// `gleamunison unpublish <name>` — retract a published name.
////
//// Admission is the evidence turnstile; retraction is the reverse. Removing a
//// name removes three things together: the name → hash line in the published
//// index, the namespace binding, and the definition's bytes in the store. Left
//// half-done, any one of them lies: an index line for absent bytes, a binding
//// to a ref nobody can load, or bytes no name reaches.
////
//// Refusals are deliberate. A name that was never published has nothing to
//// retract (exit 1). Content that another definition depends on, or another
//// name still binds, is NOT deleted: retracting one name must not break a
//// different one, and the message names what stands in the way.

import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleamunison/cli_lifecycle
import gleamunison/cli_result
import gleamunison/cli_store
import gleamunison/identity
import gleamunison/namespace
import gleamunison/storage
import gleamunison/store_deps
import simplifile

const default_branch = "main"

pub fn command(args: List(String)) -> Nil {
  case run(args) {
    Ok(message) -> io.println(message)
    Error(#(code, message)) -> cli_result.fail_with_code(code, message)
  }
}

fn run(args: List(String)) -> Result(String, #(Int, String)) {
  use #(name, store_override, branch) <- result.try(parse_args(
    args,
    None,
    None,
    default_branch,
  ))
  use context <- result.try(
    cli_lifecycle.resolve_context(store_override)
    |> result.map_error(fn(message) { #(cli_result.unresolvable, message) }),
  )
  let store_path = cli_lifecycle.store_path(context)
  let manifest_path = cli_lifecycle.manifest_path(context)
  use lines <- result.try(read_manifest(manifest_path))
  use hash <- result.try(find_name(lines, name))
  use ref <- result.try(
    identity.parse_ref_hex(hash)
    |> result.map_error(fn(message) { #(cli_result.unresolvable, message) }),
  )
  use report <- result.try(
    cli_store.with_dets_mapped(
      store_path,
      fn(adapter) {
        retract(adapter, manifest_path, name, hash, ref, branch, lines)
      },
      fn(message) { #(cli_result.unresolvable, message) },
    ),
  )
  Ok(report)
}

fn retract(
  adapter: storage.StorageAdapter,
  manifest_path: String,
  name: String,
  hash: String,
  ref: identity.DefinitionRef,
  branch: String,
  lines: List(String),
) -> Result(String, #(Int, String)) {
  // Both checks before any mutation: a refusal must leave the store exactly as
  // it was.
  use _ <- result.try(refuse_dependents(adapter, name, ref, branch))
  use _ <- result.try(refuse_other_names(adapter, name, ref, branch))
  use _ <- result.try(rewrite_manifest(manifest_path, name, lines))
  use _ <- result.try(unbind(adapter, name, branch))
  use _ <- result.try(
    adapter.delete(ref)
    |> result.map_error(fn(error) {
      #(
        cli_result.refused,
        "unpublish: cannot remove " <> hash <> ": " <> describe(error),
      )
    }),
  )
  Ok("unpublished: " <> name <> " #" <> string.slice(hash, 0, 12))
}

fn refuse_dependents(
  adapter: storage.StorageAdapter,
  name: String,
  ref: identity.DefinitionRef,
  branch: String,
) -> Result(Nil, #(Int, String)) {
  case store_deps.dependents_on_branch(adapter, branch, ref) {
    [] -> Ok(Nil)
    dependents ->
      Error(#(
        cli_result.refused,
        "unpublish: "
          <> name
          <> " is used by "
          <> int.to_string(list.length(dependents))
          <> " stored definition(s): "
          <> string.join(list.map(dependents, short), ", ")
          <> "\nunpublish: retract those first, or use `purge` to remove the set",
      ))
  }
}

fn refuse_other_names(
  adapter: storage.StorageAdapter,
  name: String,
  ref: identity.DefinitionRef,
  branch: String,
) -> Result(Nil, #(Int, String)) {
  case store_deps.other_names_on_branch(adapter, branch, ref, name) {
    [] -> Ok(Nil)
    others ->
      Error(#(
        cli_result.refused,
        "unpublish: "
          <> name
          <> "'s content is still bound as "
          <> string.join(others, ", ")
          <> "; unpublish those names instead",
      ))
  }
}

/// The binding goes with the name. A namespace without the entry is committed
/// as a new head, so the retraction is itself a durable fact in the history.
fn unbind(
  adapter: storage.StorageAdapter,
  name: String,
  branch: String,
) -> Result(Nil, #(Int, String)) {
  let ns = case namespace.load_current(adapter, branch) {
    Ok(current) -> current
    Error(_) -> namespace.empty()
  }
  namespace.commit(adapter, branch, namespace.remove(ns, name))
  |> result.map(fn(_) { Nil })
  |> result.map_error(fn(reason) {
    #(cli_result.refused, "unpublish: cannot commit the namespace: " <> reason)
  })
}

fn read_manifest(path: String) -> Result(List(String), #(Int, String)) {
  case simplifile.read(path) {
    Ok(content) -> Ok(string.split(content, "\n"))
    Error(_) -> Ok([])
  }
}

fn find_name(
  lines: List(String),
  name: String,
) -> Result(String, #(Int, String)) {
  case list.find_map(lines, fn(line) { hash_of_line(line, name) }) {
    Ok(hash) -> Ok(hash)
    Error(_) ->
      Error(#(
        cli_result.refused,
        "unpublish: " <> name <> " is not published (nothing to retract)",
      ))
  }
}

fn hash_of_line(line: String, name: String) -> Result(String, Nil) {
  case string.split_once(line, " ") {
    Ok(#(found, hash)) if found == name -> Ok(hash)
    _ -> Error(Nil)
  }
}

/// Whole-file rewrite, then an atomic replace: a crash mid-write leaves the old
/// index intact rather than a half-written one.
fn rewrite_manifest(
  path: String,
  name: String,
  lines: List(String),
) -> Result(Nil, #(Int, String)) {
  let kept =
    list.filter(lines, fn(line) {
      case string.split_once(line, " ") {
        Ok(#(found, _)) -> found != name
        Error(_) -> line != ""
      }
    })
  let content = string.join(kept, "\n") <> "\n"
  let temp = path <> ".tmp"
  use _ <- result.try(
    simplifile.write(temp, content)
    |> result.map_error(fn(error) {
      #(
        cli_result.refused,
        "unpublish: cannot write the index: " <> string.inspect(error),
      )
    }),
  )
  simplifile.rename(temp, path)
  |> result.map_error(fn(error) {
    #(
      cli_result.refused,
      "unpublish: cannot replace the index: " <> string.inspect(error),
    )
  })
}

fn parse_args(
  args: List(String),
  name: Option(String),
  store_override: Option(String),
  branch: String,
) -> Result(#(String, Option(String), String), #(Int, String)) {
  case args {
    [] ->
      case name {
        Some(value) -> Ok(#(value, store_override, branch))
        None -> Error(#(cli_result.refused, usage()))
      }
    ["--store", path, ..rest] -> parse_args(rest, name, Some(path), branch)
    ["--store"] ->
      Error(#(cli_result.refused, "--store needs a path\n" <> usage()))
    ["--branch", selected, ..rest] ->
      parse_args(rest, name, store_override, selected)
    ["--branch"] ->
      Error(#(cli_result.refused, "--branch needs a name\n" <> usage()))
    [value, ..rest] ->
      case name {
        Some(_) ->
          Error(#(
            cli_result.refused,
            "unpublish: unexpected argument '" <> value <> "'\n" <> usage(),
          ))
        None -> parse_args(rest, Some(value), store_override, branch)
      }
  }
}

fn describe(error: storage.StorageError) -> String {
  case error {
    storage.StorageError(message) -> message
    storage.NotFound -> "not found"
    storage.IoError(reason) -> reason
  }
}

fn short(ref: identity.DefinitionRef) -> String {
  string.slice(store_deps.hex(ref), 0, 12)
}

fn usage() -> String {
  "usage: gleam run -- unpublish <name> [--store path] [--branch name]\n"
  <> "\n"
  <> "Retracts a published name: its index line, its namespace binding, and\n"
  <> "its definition bytes. Refuses when another stored definition depends on\n"
  <> "it, or when another name still binds the same content.\n"
  <> "The branch defaults to main; --branch selects another namespace."
}
