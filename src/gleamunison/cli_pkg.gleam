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
import gleamunison/cli_publish
import gleamunison/cli_result
import gleamunison/cli_store
import gleamunison/codebase
import gleamunison/elab_types
import gleamunison/manifest
import gleamunison/pkg
import gleamunison/storage
import gleamunison/sync
import gleamunison/sync_types.{PeerId}
import gleamunison/verify

const default_store = ".gleamunison/store.dets"

pub fn command(args: List(String)) -> Result(Nil, String) {
  case args {
    ["install", ..rest] -> install(rest)
    ["publish", ..rest] -> publish(rest)
    _ ->
      Error(
        "usage: gleam run -- pkg install <manifest-hash> [--peer host:port] [--branch name]\n"
        <> "       gleam run -- pkg publish <file.lisp> --name <pkg> --version <v>",
      )
  }
}

fn publish(args: List(String)) -> Result(Nil, String) {
  use #(path, name, version) <- result.try(parse_publish_args(
    args,
    None,
    None,
    None,
  ))
  use output <- result.try(
    cli_store.with_dets(default_store, fn(adapter) {
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
      use pairs <- result.try(
        cli_publish.hash_defs(term_names, defs, cache, []),
      )
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

fn install(args: List(String)) -> Result(Nil, String) {
  use #(hash_hex, peer, branch, store_path) <- result.try(parse_args(
    args,
    None,
    None,
    default_store,
  ))
  use _ <- result.try(manifest.ref_from_hex(hash_hex))
  use output <- result.try(
    cli_store.with_dets(store_path, fn(adapter) {
      use _ <- result.try(case peer {
        None -> Ok(Nil)
        Some(p) -> pull_first(p, adapter, hash_hex)
      })
      pkg.install_from_store_production(adapter, hash_hex, branch)
      |> result.map(fn(installed) {
        "pkg: installed "
        <> string.join(installed, ", ")
        <> " onto branch "
        <> branch
      })
    }),
  )
  cli_result.success(output)
}

fn parse_args(
  args: List(String),
  hash: Option(String),
  peer: Option(String),
  store: String,
) -> Result(#(String, Option(String), String, String), String) {
  case args {
    [] ->
      case hash {
        None ->
          Error(
            "usage: gleam run -- pkg install <manifest-hash> [--peer host:port] [--branch name]",
          )
        Some(h) -> Ok(#(h, peer, "main", store))
      }
    ["--peer", p, ..rest] -> parse_args(rest, hash, Some(p), store)
    ["--peer"] -> Error("--peer needs host:port")
    ["--branch", b, ..rest] ->
      case hash {
        None -> Error("--branch needs the manifest hash first")
        Some(_) -> parse_args_with_branch(rest, hash, peer, store, b)
      }
    ["--store", path, ..rest] -> parse_args(rest, hash, peer, path)
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
  store: String,
  branch: String,
) -> Result(#(String, Option(String), String, String), String) {
  case rest {
    [] ->
      case hash {
        Some(h) -> Ok(#(h, peer, branch, store))
        None -> Error("missing manifest hash")
      }
    ["--store", path, ..more] ->
      parse_args_with_branch(more, hash, peer, path, branch)
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
  cli_result.success(
    "pkg: pulled "
    <> int.to_string(list.length(closure.manifests))
    <> " manifests, "
    <> int.to_string(list.length(closure.defs))
    <> " defs from "
    <> peer,
  )
}
