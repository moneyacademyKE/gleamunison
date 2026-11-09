//// `gleamunison purge <content-hash> [--yes]` — remove a definition, and the
//// dependencies nothing else keeps alive.
////
//// Dry run by default: the command prints exactly what it would remove and
//// changes nothing until `--yes`. Two refusals come first and neither depends
//// on `--yes`, because both describe a store that would be broken by the
//// removal:
////
////   - something outside the removal set depends on it (unpublish or purge
////     those first);
////   - the ref is not in the store at all (exit 2: nothing to remove).
////
//// Removing bytes also removes the names that pointed at them, in the index
//// and the namespace. A name left behind would resolve to a ref nobody can
//// load — the exact lie `unpublish` exists to prevent.

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
import gleamunison/identity.{type DefinitionRef, ref_hex, short_ref_hex}
import gleamunison/namespace
import gleamunison/publication_index
import gleamunison/storage
import gleamunison/store_deps

pub fn command(args: List(String)) -> Nil {
  case run(args) {
    Ok(message) -> io.println(message)
    Error(#(code, message)) -> cli_result.fail_with_code(code, message)
  }
}

fn run(args: List(String)) -> Result(String, #(Int, String)) {
  use #(hash, confirmed, store_override, branch) <- result.try(parse_args(
    args,
    None,
    False,
    cli_lifecycle.flag_tail(cli_lifecycle.default_branch),
  ))
  use ref <- result.try(
    identity.parse_ref_hex(hash)
    |> result.map_error(fn(message) { #(cli_result.unresolvable, message) }),
  )
  use context <- result.try(
    cli_lifecycle.resolve_context(store_override)
    |> result.map_error(fn(message) { #(cli_result.unresolvable, message) }),
  )
  let store_path = cli_lifecycle.store_path(context)
  let manifest_path = cli_lifecycle.manifest_path(context)
  cli_store.with_dets_mapped(
    store_path,
    fn(adapter) { purge(adapter, manifest_path, ref, branch, confirmed) },
    fn(message) { #(cli_result.unresolvable, message) },
  )
}

pub fn purge(
  adapter: storage.StorageAdapter,
  manifest_path: String,
  ref: DefinitionRef,
  branch: String,
  confirmed: Bool,
) -> Result(String, #(Int, String)) {
  use _ <- result.try(exists(adapter, ref))
  use snapshot <- result.try(
    dependency_snapshot.read(adapter, branch)
    |> result.map_error(fn(error) {
      #(
        cli_result.refused,
        "purge: cannot inspect store: "
          <> dependency_snapshot.describe_error(error),
      )
    }),
  )
  // Bytes are shared by every branch; the snapshot above is one branch. A
  // ref still bound elsewhere is a reason not to remove it, whatever the
  // selected branch says.
  use _ <- result.try(
    store_deps.branches_binding_elsewhere(adapter, ref, branch)
    |> result.map_error(fn(error) {
      #(
        cli_result.refused,
        "purge: cannot read branch bindings: "
          <> store_deps.describe_dependency_error(error),
      )
    })
    |> result.try(fn(held) {
      case held {
        [] -> Ok(Nil)
        _ ->
          Error(#(
            cli_result.refused,
            "purge: "
              <> short_ref_hex(ref)
              <> " is still bound on "
              <> store_deps.describe_branch_bindings(held)
              <> "\npurge: bytes are shared by every branch; retract it there first",
          ))
      }
    }),
  )
  let outside = dependency_snapshot.dependents(snapshot, ref)
  case outside {
    [] -> {
      let removal = dependency_snapshot.exclusive_closure(snapshot, ref)
      let report = describe_set(snapshot, removal)
      case confirmed {
        False ->
          Ok(
            "purge: would remove "
            <> int.to_string(list.length(removal))
            <> " definition(s):\n"
            <> report
            <> "\npurge: nothing changed; re-run with --yes to remove them",
          )
        True -> {
          use _ <- result.try(remove_all(
            adapter,
            manifest_path,
            branch,
            removal,
            snapshot,
          ))
          Ok(
            "purge: removed "
            <> int.to_string(list.length(removal))
            <> " definition(s):\n"
            <> report
            <> "\n",
          )
        }
      }
    }
    _ ->
      Error(#(
        cli_result.refused,
        "purge: "
          <> short_ref_hex(ref)
          <> " is used by "
          <> int.to_string(list.length(outside))
          <> " stored definition(s) outside the removal set: "
          <> string.join(list.map(outside, short_ref_hex), ", ")
          <> "\npurge: retract or purge those first",
      ))
  }
}

fn exists(
  adapter: storage.StorageAdapter,
  ref: DefinitionRef,
) -> Result(Nil, #(Int, String)) {
  case adapter.lookup(ref) {
    Ok(Some(_)) -> Ok(Nil)
    Ok(None) ->
      Error(#(
        cli_result.unresolvable,
        "purge: not in the store: " <> short_ref_hex(ref),
      ))
    Error(error) ->
      Error(#(
        cli_result.unresolvable,
        "purge: " <> storage.describe_error(error),
      ))
  }
}

/// One line per definition: ref, and the names that point at it.
fn describe_set(
  snapshot: dependency_snapshot.Snapshot,
  removal: List(DefinitionRef),
) -> String {
  removal
  |> list.map(fn(ref) {
    let names = dependency_snapshot.names(snapshot, ref)
    case names {
      [] -> "  " <> short_ref_hex(ref)
      _ ->
        "  " <> short_ref_hex(ref) <> "  (" <> string.join(names, ", ") <> ")"
    }
  })
  |> string.join("\n")
}

fn remove_all(
  adapter: storage.StorageAdapter,
  manifest_path: String,
  branch: String,
  removal: List(DefinitionRef),
  snapshot: dependency_snapshot.Snapshot,
) -> Result(Nil, #(Int, String)) {
  // All reads precede mutation. Missing index is valid for hash-only stores;
  // an unreadable index is not an empty one.
  use lines <- result.try(
    publication_index.read(manifest_path)
    |> result.map_error(publication_index.describe("purge", _)),
  )
  let hashes = list.map(removal, ref_hex)
  use _ <- result.try(unbind_all(adapter, branch, removal, snapshot))
  use _ <- result.try(drop_index_lines(manifest_path, hashes, lines))
  use _ <- result.try(
    list.try_fold(removal, Nil, fn(_, ref) {
      adapter.delete(ref)
      |> result.map_error(fn(error) {
        #(
          cli_result.refused,
          "purge: cannot remove "
            <> short_ref_hex(ref)
            <> ": "
            <> storage.describe_error(error),
        )
      })
    }),
  )
  Ok(Nil)
}

/// Drop the namespace bindings for every removed ref, in one commit.
fn unbind_all(
  adapter: storage.StorageAdapter,
  branch: String,
  removal: List(DefinitionRef),
  snapshot: dependency_snapshot.Snapshot,
) -> Result(Nil, #(Int, String)) {
  let current = dependency_snapshot.current_namespace(snapshot)
  let names =
    list.flat_map(removal, fn(ref) { dependency_snapshot.names(snapshot, ref) })
  case names {
    [] -> Ok(Nil)
    _ -> {
      let next =
        list.fold(names, current, fn(ns, name) { namespace.remove(ns, name) })
      namespace.commit(adapter, branch, next)
      |> result.map(fn(_) { Nil })
      |> result.map_error(fn(reason) {
        #(cli_result.refused, "purge: cannot commit the namespace: " <> reason)
      })
    }
  }
}

/// Remove index lines whose hash is in the removed set — the names that pointed
/// at bytes purge is about to delete. The atomic replace is publication_index's.
fn drop_index_lines(
  path: String,
  hashes: List(String),
  lines: List(publication_index.Line),
) -> Result(Nil, #(Int, String)) {
  publication_index.rewrite(path, lines, fn(_, hash) {
    !list.contains(hashes, hash)
  })
  |> result.map_error(publication_index.describe("purge", _))
}

fn parse_args(
  args: List(String),
  hash: Option(String),
  confirmed: Bool,
  tail: cli_lifecycle.FlagTail,
) -> Result(#(String, Bool, Option(String), String), #(Int, String)) {
  case cli_lifecycle.take_flag(args, tail) {
    cli_lifecycle.Taken(next, rest) -> parse_args(rest, hash, confirmed, next)
    cli_lifecycle.MissingValue(flag) ->
      Error(cli_lifecycle.flag_missing_error(flag, usage()))
    cli_lifecycle.NotTailFlag ->
      case args {
        [] ->
          case hash {
            Some(value) -> Ok(#(value, confirmed, tail.store, tail.branch))
            None -> Error(#(cli_result.refused, usage()))
          }
        ["--yes"] -> parse_args([], hash, True, tail)
        [value, ..rest] ->
          case hash {
            Some(_) ->
              Error(#(
                cli_result.refused,
                "purge: unexpected argument '" <> value <> "'\n" <> usage(),
              ))
            None -> parse_args(rest, Some(value), confirmed, tail)
          }
      }
  }
}

fn usage() -> String {
  "usage: gleam run -- purge <content-hash> [--yes] [--store path] [--branch name]\n"
  <> "\n"
  <> "Removes a definition and the stored dependencies nothing else uses.\n"
  <> "Dry run by default: prints the removal set and changes nothing until\n"
  <> "--yes. Refuses when something outside that set depends on the ref.\n"
  <> "The branch defaults to main; --branch selects another namespace."
}
