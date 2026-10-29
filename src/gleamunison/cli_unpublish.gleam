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
import gleamunison/dependency_snapshot
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
  use report <- result.try(
    cli_store.with_dets_mapped(
      store_path,
      fn(adapter) {
        use #(hash, ref) <- result.try(resolve_target(
          adapter,
          lines,
          name,
          branch,
        ))
        retract(adapter, manifest_path, name, hash, ref, branch, lines)
      },
      fn(message) { #(cli_result.unresolvable, message) },
    ),
  )
  Ok(report)
}

/// Which content this name means on this branch.
///
/// The published index is store-wide; a binding is per-branch. Retracting on
/// one branch removes the index line, so a second branch holding the same
/// name had no line left to find and could never be retracted. The index is
/// tried first (it is what `publish` wrote), then the branch namespace, which
/// is the authority for its own bindings.
pub fn resolve_target(
  adapter: storage.StorageAdapter,
  lines: List(String),
  name: String,
  branch: String,
) -> Result(#(String, identity.DefinitionRef), #(Int, String)) {
  case find_name(lines, name) {
    Ok(hash) ->
      identity.parse_ref_hex(hash)
      |> result.map(fn(ref) { #(hash, ref) })
      |> result.map_error(fn(message) { #(cli_result.unresolvable, message) })
    Error(_) ->
      case namespace.load_current(adapter, branch) {
        Ok(ns) ->
          case namespace.get(ns, name) {
            Ok(ref) -> Ok(#(identity.ref_hex(ref), ref))
            Error(_) -> Error(not_published(name))
          }
        // A branch that does not exist has no binding to retract; a
        // store that cannot be read is a different failure, and saying
        // "not published" would hide it.
        Error(reason) ->
          case string.starts_with(reason, "no such branch") {
            True -> Error(not_published(name))
            False ->
              Error(#(
                cli_result.refused,
                "unpublish: cannot read branch " <> branch <> ": " <> reason,
              ))
          }
      }
  }
}

fn not_published(name: String) -> #(Int, String) {
  #(
    cli_result.refused,
    "unpublish: " <> name <> " is not published (nothing to retract)",
  )
}

pub fn retract(
  adapter: storage.StorageAdapter,
  manifest_path: String,
  name: String,
  hash: String,
  ref: identity.DefinitionRef,
  branch: String,
  lines: List(String),
) -> Result(String, #(Int, String)) {
  use snapshot <- result.try(
    dependency_snapshot.read(adapter, branch)
    |> result.map_error(fn(error) {
      #(
        cli_result.refused,
        "unpublish: cannot inspect store: " <> string.inspect(error),
      )
    }),
  )
  // Bytes are shared by every branch; the snapshot above is one branch. A
  // name still bound elsewhere is a reason not to delete them.
  use held <- result.try(
    store_deps.branches_binding_elsewhere(adapter, ref, branch)
    |> result.map_error(fn(error) {
      #(
        cli_result.refused,
        "unpublish: cannot read branch bindings: "
          <> store_deps.describe_dependency_error(error),
      )
    }),
  )
  let dependents = dependency_snapshot.dependents(snapshot, ref)
  let aliases =
    dependency_snapshot.names(snapshot, ref)
    |> list.filter(fn(other) { other != name })
  case dependents, aliases {
    [], [] -> {
      let ns = dependency_snapshot.current_namespace(snapshot)
      use _ <- result.try(
        namespace.commit(adapter, branch, namespace.remove(ns, name))
        |> result.map_error(fn(reason) {
          #(
            cli_result.refused,
            "unpublish: cannot commit the namespace: " <> reason,
          )
        }),
      )
      use _ <- result.try(rewrite_manifest(manifest_path, name, lines))
      // The name is branch-scoped; the bytes are not. Two branches binding the
      // same content cannot both retract first, so refusing while another
      // branch holds it would be a deadlock. Delete the bytes only when no other
      // branch still resolves to them, and say where they stay when one does.
      drop_bytes_unless_held(adapter, ref, hash, name, held)
    }

    [_, ..], _ ->
      Error(#(
        cli_result.refused,
        "unpublish: "
          <> name
          <> " is used by "
          <> int.to_string(list.length(dependents))
          <> " stored definition(s): "
          <> string.join(list.map(dependents, identity.short_ref_hex), ", ")
          <> "\nunpublish: retract those first, or use `purge` to remove the set",
      ))
    _, [_, ..] ->
      Error(#(
        cli_result.refused,
        "unpublish: "
          <> name
          <> "'s content is still bound as "
          <> string.join(aliases, ", ")
          <> "; unpublish those names instead",
      ))
  }
}

/// The bytes are the only shared thing here: remove them when this was the
/// last branch holding the content, and leave them when another branch still
/// resolves to them, naming that branch instead of deleting under it.
fn drop_bytes_unless_held(
  adapter: storage.StorageAdapter,
  ref: identity.DefinitionRef,
  hash: String,
  name: String,
  held: List(#(String, String)),
) -> Result(String, #(Int, String)) {
  case held {
    [] -> {
      use _ <- result.try(
        adapter.delete(ref)
        |> result.map_error(fn(error) {
          #(
            cli_result.refused,
            "unpublish: cannot remove "
              <> hash
              <> ": "
              <> storage.describe_error(error),
          )
        }),
      )
      Ok("unpublished: " <> name <> " #" <> identity.short_hash_hex(hash))
    }
    _ ->
      Ok(
        "unpublished: "
        <> name
        <> " #"
        <> identity.short_hash_hex(hash)
        <> " (bytes kept: still bound on "
        <> store_deps.describe_branch_bindings(held)
        <> ")",
      )
  }
}

fn read_manifest(path: String) -> Result(List(String), #(Int, String)) {
  case simplifile.read(path) {
    Ok(content) -> Ok(string.split(content, "\n"))
    Error(simplifile.Enoent) -> Ok([])
    Error(error) ->
      Error(#(
        cli_result.refused,
        "unpublish: cannot read the index: " <> string.inspect(error),
      ))
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

fn usage() -> String {
  "usage: gleam run -- unpublish <name> [--store path] [--branch name]\n"
  <> "\n"
  <> "Retracts a published name: its index line, its namespace binding, and\n"
  <> "its definition bytes. Refuses when another stored definition depends on\n"
  <> "it, or when another name still binds the same content.\n"
  <> "The branch defaults to main; --branch selects another namespace."
}
