//// `gleamunison pkg install <manifest-hash> [--peer host:port] [--branch name]`
////
//// With --peer: pull the peer's chunks first (sync carries definitions,
//// manifests, and evidence alike — everything is content-addressed).
//// Then install from the local store: manifest integrity re-hash, the
//// evidence turnstile, and a namespace commit on the branch.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleamunison/cli_lifecycle
import gleamunison/cli_result
import gleamunison/cli_store
import gleamunison/codebase
import gleamunison/elab_types
import gleamunison/manifest
import gleamunison/pkg
import gleamunison/publication
import gleamunison/storage
import gleamunison/sync
import gleamunison/sync_types.{PeerId}
import gleamunison/verify

const default_branch = "main"

pub fn command(args: List(String)) -> Result(Nil, #(Int, String)) {
  case args {
    ["install", ..rest] -> install(rest)
    ["publish", ..rest] ->
      publish_outcome(rest)
      |> result.map_error(fn(message) { #(cli_result.refused, message) })
    _ ->
      Error(#(
        cli_result.refused,
        "usage: gleam run -- pkg install <manifest-hash> [--peer host:port] [--branch name]\n"
          <> "       gleam run -- pkg publish <file.lisp> --name <pkg> --version <v>",
      ))
  }
}

fn publish_outcome(args: List(String)) -> Result(Nil, String) {
  use #(path, name, version) <- result.try(parse_publish_args(
    args,
    None,
    None,
    None,
  ))
  use context <- result.try(cli_lifecycle.resolve_context(None))
  let store_path = cli_lifecycle.store_path(context)
  use output <- result.try(
    cli_store.with_dets(store_path, fn(adapter) {
      use #(cache, defs, file_names) <- result.try(verify.load_defs_file_scoped(
        path,
      ))
      let term_names =
        list.filter_map(defs, fn(pair) {
          case pair.1 {
            elab_types.SurfaceTermDef(_) ->
              case list.contains(file_names, pair.0) {
                True -> Ok(pair.0)
                False -> Error(Nil)
              }
            _ -> Error(Nil)
          }
        })
      use pairs <- result.try(publication.hash_defs(term_names, defs, cache))
      pkg.publish_to_store_production(adapter, pairs, name, version)
      |> result.map(fn(hex) {
        "pkg: published " <> name <> " " <> version <> " as\n" <> hex
      })
      |> result.map_error(fn(missing) {
        "pkg: REFUSED — no passing test evidence for: "
        <> string.join(missing, ", ")
        <> "\npkg: run `gleam run -- test "
        <> path
        <> "` first; evidence attaches to the content hash."
      })
    }),
  )
  cli_result.success(output)
}

fn parse_publish_args(
  args: List(String),
  path: Option(String),
  name: Option(String),
  version: Option(String),
) -> Result(#(String, String, String), String) {
  case args {
    [] ->
      case path, name, version {
        Some(p), Some(n), Some(v) -> Ok(#(p, n, v))
        _, _, _ ->
          Error(
            "usage: gleam run -- pkg publish <file.lisp> --name <pkg> --version <v>",
          )
      }
    ["--name", n, ..rest] -> parse_publish_args(rest, path, Some(n), version)
    ["--version", v, ..rest] -> parse_publish_args(rest, path, name, Some(v))
    [p, ..rest] ->
      case path {
        None -> parse_publish_args(rest, Some(p), name, version)
        Some(_) -> Error("unknown argument: " <> p)
      }
  }
}

fn install(args: List(String)) -> Result(Nil, #(Int, String)) {
  use #(hash_hex, peer, branch, store_override) <- result.try(
    parse_args(args, None, None, None)
    |> result.map_error(fn(message) { #(cli_result.refused, message) }),
  )
  use context <- result.try(
    cli_lifecycle.resolve_context(store_override)
    |> result.map_error(fn(message) { #(cli_result.refused, message) }),
  )
  let store_path = cli_lifecycle.store_path(context)
  use _ <- result.try(
    manifest.ref_from_hex(hash_hex)
    |> result.map(fn(_) { Nil })
    |> result.map_error(fn(message) { #(cli_result.unresolvable, message) }),
  )
  use output <- result.try(cli_store.with_dets_mapped(
    store_path,
    fn(adapter) {
      use _ <- result.try(case peer {
        None -> Ok(Nil)
        Some(p) ->
          pull_first(p, adapter, hash_hex)
          |> result.map_error(fn(message) {
            #(cli_result.unresolvable, message)
          })
      })
      // Every manifest the install will read must already be in the store.
      // Walking the graph first is what makes a missing manifest
      // could-not-resolve (exit 2) instead of a refusal, and it names the
      // absent hash before any policy is consulted.
      use _ <- result.try(
        pkg.manifest_closure(adapter, hash_hex)
        |> result.map(fn(_) { Nil })
        |> result.map_error(fn(reason) {
          #(cli_result.unresolvable, "pkg: " <> reason)
        }),
      )
      pkg.install_from_store_production(adapter, hash_hex, branch)
      |> result.map(fn(installed) {
        "pkg: installed "
        <> string.join(installed, ", ")
        <> " onto branch "
        <> branch
      })
      |> result.map_error(fn(reason) { #(cli_result.refused, reason) })
    },
    fn(message) { #(cli_result.refused, message) },
  ))
  cli_result.success_coded(output)
}

fn parse_args(
  args: List(String),
  hash: Option(String),
  peer: Option(String),
  store: Option(String),
) -> Result(#(String, Option(String), String, Option(String)), String) {
  case args {
    [] ->
      case hash {
        None ->
          Error(
            "usage: gleam run -- pkg install <manifest-hash> [--peer host:port] [--branch name]",
          )
        Some(h) -> Ok(#(h, peer, default_branch, store))
      }
    ["--peer", p, ..rest] -> parse_args(rest, hash, Some(p), store)
    ["--peer"] -> Error("--peer needs host:port")
    ["--branch", b, ..rest] ->
      case hash {
        None -> Error("--branch needs the manifest hash first")
        Some(_) -> parse_args_with_branch(rest, hash, peer, store, b)
      }
    ["--store", path, ..rest] -> parse_args(rest, hash, peer, Some(path))
    [h, ..rest] ->
      case hash {
        None -> parse_args(rest, Some(h), peer, store)
        Some(_) -> Error("unknown argument: " <> h)
      }
  }
}

// Branch overrides "main"; kept out of parse_args' accumulator for clarity.
fn parse_args_with_branch(
  rest: List(String),
  hash: Option(String),
  peer: Option(String),
  store: Option(String),
  branch: String,
) -> Result(#(String, Option(String), String, Option(String)), String) {
  case rest {
    [] ->
      case hash {
        Some(h) -> Ok(#(h, peer, branch, store))
        None -> Error("missing manifest hash")
      }
    ["--store", path, ..more] ->
      parse_args_with_branch(more, hash, peer, Some(path), branch)
    ["--peer", p, ..more] ->
      parse_args_with_branch(more, hash, Some(p), store, branch)
    [other, ..] -> Error("unknown argument: " <> other)
  }
}

// Selective pull: transfer only the package's manifest closure from the
// peer (manifests walked iteratively, defs in one batch), with the
// sync layer's unsolicited-chunk and conflict checks on every chunk.
fn pull_first(
  peer: String,
  adapter: storage.StorageAdapter,
  root_hex: String,
) -> Result(Nil, String) {
  use _ <- result.try(
    sync.connect(PeerId(peer))
    |> result.map_error(fn(_) { "pkg: cannot connect to peer " <> peer }),
  )
  let cb = codebase.with_adapter(adapter)
  let fetch = fn(hexes: List(String)) -> Result(Nil, String) {
    sync.fetch_refs(PeerId(peer), cb, hexes)
    |> result.map(fn(_) { Nil })
    |> result.map_error(fn(e) { string.inspect(e) })
  }
  use closure <- result.try(pkg.pull_closure(adapter, root_hex, fetch))
  // The closure is content; admission is a claim about it. Pull the peer's
  // attestations for exactly those subjects, or the evidence gate below can
  // never pass and `--peer` refuses every install.
  use _ <- result.try(
    sync.fetch_evidence(PeerId(peer), cb, closure.defs)
    |> result.map(fn(_) { Nil })
    |> result.map_error(fn(e) {
      "pkg: cannot fetch evidence: " <> string.inspect(e)
    }),
  )
  cli_result.success(
    "pkg: pulled "
    <> int.to_string(list.length(closure.manifests))
    <> " manifests, "
    <> int.to_string(list.length(closure.defs))
    <> " defs from "
    <> peer,
  )
}
