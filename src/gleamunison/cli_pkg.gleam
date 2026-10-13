//// `gleamunison pkg install <manifest-hash> [--peer host:port] [--branch name]`
////
//// With --peer: pull the peer's chunks first (sync carries definitions,
//// manifests, and evidence alike — everything is content-addressed).
//// Then install from the local store: manifest integrity re-hash, the
//// evidence turnstile, and a namespace commit on the branch.

import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleamunison/cli_publish
import gleamunison/codebase
import gleamunison/elab_types
import gleamunison/pkg
import gleamunison/storage
import gleamunison/sync
import gleamunison/sync_types.{PeerId}
import gleamunison/verify
import simplifile

const default_store = ".gleamunison/store.dets"

pub fn command(args: List(String)) -> Nil {
  case args {
    ["install", ..rest] -> install(rest)
    ["publish", ..rest] -> publish(rest)
    _ ->
      io.println(
        "usage: gleam run -- pkg install <manifest-hash> [--peer host:port] [--branch name]\n"
        <> "       gleam run -- pkg publish <file.lisp> --name <pkg> --version <v>",
      )
  }
}

fn publish(args: List(String)) -> Nil {
  case parse_publish_args(args, None, None, None) {
    Error(err) -> io.println("pkg: " <> err)
    Ok(#(path, name, version)) -> run_publish(path, name, version)
  }
}

fn parse_publish_args(
  args: List(String),
  path: Option(String),
  name: Option(String),
  version: Option(String),
) -> Result(#(String, String, String), String) {
  case args {
    [] ->
      case #(path, name, version) {
        #(Some(p), Some(n), Some(v)) -> Ok(#(p, n, v))
        _ ->
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

fn run_publish(path: String, name: String, version: String) -> Nil {
  let _ = simplifile.create_directory_all(".gleamunison")
  case storage.dets(default_store) {
    Error(_) -> io.println("pkg: cannot open store at " <> default_store)
    Ok(adapter) ->
      case verify.load_defs_file_scoped(path) {
        Error(err) -> io.println("pkg: " <> err)
        Ok(#(cache, defs, file_names)) -> {
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
          case cli_publish.hash_defs(term_names, defs, cache, []) {
            Error(err) -> io.println("pkg: " <> err)
            Ok(pairs) ->
              case pkg.publish_to_store(adapter, pairs, name, version) {
                Error(missing) ->
                  io.println(
                    "pkg: REFUSED — no passing test evidence for: "
                    <> string.join(missing, ", ")
                    <> "\npkg: run `gleam run -- test "
                    <> path
                    <> "` first; evidence attaches to the content hash.",
                  )
                Ok(hex) -> {
                  io.println(
                    "pkg: published " <> name <> " " <> version <> " as",
                  )
                  io.println(hex)
                }
              }
          }
        }
      }
  }
}

fn install(args: List(String)) -> Nil {
  case parse_args(args, None, None, default_store) {
    Error(err) -> io.println("pkg: " <> err)
    Ok(#(hash_hex, peer, branch, store_path)) ->
      run(hash_hex, peer, branch, store_path)
  }
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

fn run(
  hash_hex: String,
  peer: Option(String),
  branch: String,
  store_path: String,
) -> Nil {
  let _ = simplifile.create_directory_all(".gleamunison")
  case storage.dets(store_path) {
    Error(_) -> io.println("pkg: cannot open store at " <> store_path)
    Ok(adapter) -> {
      case peer {
        None -> Nil
        Some(p) -> pull_first(p, adapter)
      }
      case pkg.install_from_store(adapter, hash_hex, branch) {
        Ok(installed) ->
          io.println(
            "pkg: installed "
            <> string.join(installed, ", ")
            <> " onto branch "
            <> branch,
          )
        Error(err) -> io.println("pkg: " <> err)
      }
    }
  }
}

fn pull_first(peer: String, adapter: storage.StorageAdapter) -> Nil {
  let cb = codebase.with_adapter(adapter)
  case sync.pull_sync(sync.new_sync_state(), PeerId(peer), cb) {
    Ok(#(_, _, new_refs)) ->
      io.println(
        "pkg: pulled "
        <> string.inspect(list.length(new_refs))
        <> " chunks from "
        <> peer,
      )
    Error(err) -> io.println("pkg: peer sync failed: " <> string.inspect(err))
  }
}
