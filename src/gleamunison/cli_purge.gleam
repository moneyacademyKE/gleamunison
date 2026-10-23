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
import gleamunison/identity.{type DefinitionRef, Ref, hash_to_debug_string}
import gleamunison/namespace
import gleamunison/storage
import gleamunison/store_deps
import simplifile

const branch = "main"

pub fn command(args: List(String)) -> Nil {
  case run(args) {
    Ok(message) -> io.println(message)
    Error(#(code, message)) -> cli_result.fail_with_code(code, message)
  }
}

fn run(args: List(String)) -> Result(String, #(Int, String)) {
  use #(hash, confirmed, store_override) <- result.try(parse_args(
    args,
    None,
    False,
    None,
  ))
  use ref <- result.try(
    identity.parse_ref_hex(hash)
    |> result.map_error(fn(message) { #(cli_result.unresolvable, message) }),
  )
  use store_path <- result.try(resolve(store_override))
  use manifest_path <- result.try(
    cli_lifecycle.resolve_manifest_path()
    |> result.map_error(fn(message) { #(cli_result.unresolvable, message) }),
  )
  cli_store.with_dets_mapped(
    store_path,
    fn(adapter) { purge(adapter, manifest_path, ref, confirmed) },
    fn(message) { #(cli_result.unresolvable, message) },
  )
}

fn purge(
  adapter: storage.StorageAdapter,
  manifest_path: String,
  ref: DefinitionRef,
  confirmed: Bool,
) -> Result(String, #(Int, String)) {
  use _ <- result.try(exists(adapter, ref))
  let outside =
    store_deps.dependents(adapter, ref)
    |> list.filter(fn(dependent) { dependent != ref })
  case outside {
    [] -> {
      let removal = store_deps.exclusive_closure(adapter, ref)
      let report = describe_set(adapter, removal)
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
          use _ <- result.try(remove_all(adapter, manifest_path, removal))
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
          <> short(ref)
          <> " is used by "
          <> int.to_string(list.length(outside))
          <> " stored definition(s) outside the removal set: "
          <> string.join(list.map(outside, short), ", ")
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
        "purge: not in the store: " <> short(ref),
      ))
    Error(error) ->
      Error(#(cli_result.unresolvable, "purge: " <> describe(error)))
  }
}

/// One line per definition: ref, and the names that point at it.
fn describe_set(
  adapter: storage.StorageAdapter,
  removal: List(DefinitionRef),
) -> String {
  removal
  |> list.map(fn(ref) {
    let names = store_deps.names_for(adapter, ref)
    case names {
      [] -> "  " <> short(ref)
      _ -> "  " <> short(ref) <> "  (" <> string.join(names, ", ") <> ")"
    }
  })
  |> string.join("\n")
}

fn remove_all(
  adapter: storage.StorageAdapter,
  manifest_path: String,
  removal: List(DefinitionRef),
) -> Result(Nil, #(Int, String)) {
  let hashes = list.map(removal, full_hex)
  use _ <- result.try(unbind_all(adapter, removal))
  use _ <- result.try(drop_index_lines(manifest_path, hashes))
  use _ <- result.try(
    list.try_fold(removal, Nil, fn(_, ref) {
      adapter.delete(ref)
      |> result.map_error(fn(error) {
        #(
          cli_result.refused,
          "purge: cannot remove " <> short(ref) <> ": " <> describe(error),
        )
      })
    }),
  )
  Ok(Nil)
}

/// Drop the namespace bindings for every removed ref, in one commit.
fn unbind_all(
  adapter: storage.StorageAdapter,
  removal: List(DefinitionRef),
) -> Result(Nil, #(Int, String)) {
  let current = case namespace.load_current(adapter, branch) {
    Ok(found) -> found
    Error(_) -> namespace.empty()
  }
  let names =
    list.flat_map(removal, fn(ref) { store_deps.names_for(adapter, ref) })
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

/// Remove index lines whose hash is in the removed set, atomically.
fn drop_index_lines(
  path: String,
  hashes: List(String),
) -> Result(Nil, #(Int, String)) {
  let lines = case simplifile.read(path) {
    Ok(content) -> string.split(content, "\n")
    Error(_) -> []
  }
  let kept =
    list.filter(lines, fn(line) {
      case string.split_once(line, " ") {
        Ok(#(_, hash)) -> !list.contains(hashes, hash)
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
        "purge: cannot write the index: " <> string.inspect(error),
      )
    }),
  )
  simplifile.rename(temp, path)
  |> result.map_error(fn(error) {
    #(
      cli_result.refused,
      "purge: cannot replace the index: " <> string.inspect(error),
    )
  })
}

fn parse_args(
  args: List(String),
  hash: Option(String),
  confirmed: Bool,
  store_override: Option(String),
) -> Result(#(String, Bool, Option(String)), #(Int, String)) {
  case args {
    [] ->
      case hash {
        Some(value) -> Ok(#(value, confirmed, store_override))
        None -> Error(#(cli_result.refused, usage()))
      }
    ["--yes"] -> parse_args([], hash, True, store_override)
    ["--store", path, ..rest] -> parse_args(rest, hash, confirmed, Some(path))
    ["--store"] ->
      Error(#(cli_result.refused, "--store needs a path\n" <> usage()))
    [value, ..rest] ->
      case hash {
        Some(_) ->
          Error(#(
            cli_result.refused,
            "purge: unexpected argument '" <> value <> "'\n" <> usage(),
          ))
        None -> parse_args(rest, Some(value), confirmed, store_override)
      }
  }
}

fn resolve(override: Option(String)) -> Result(String, #(Int, String)) {
  case override {
    Some(path) -> Ok(path)
    None ->
      cli_lifecycle.resolve_store_path()
      |> result.map_error(fn(message) { #(cli_result.unresolvable, message) })
  }
}

fn short(ref: DefinitionRef) -> String {
  string.slice(full_hex(ref), 0, 12)
}

fn full_hex(ref: DefinitionRef) -> String {
  let Ref(hash) = ref
  hash_to_debug_string(hash)
}

fn describe(error: storage.StorageError) -> String {
  case error {
    storage.StorageError(message) -> message
    storage.NotFound -> "not found"
    storage.IoError(reason) -> reason
  }
}

fn usage() -> String {
  "usage: gleam run -- purge <content-hash> [--yes] [--store path]\n"
  <> "\n"
  <> "Removes a definition and the stored dependencies nothing else uses.\n"
  <> "Dry run by default: prints the removal set and changes nothing until\n"
  <> "--yes. Refuses when something outside that set depends on the ref."
}
