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
import gleamunison/codebase
import gleamunison/pkg
import gleamunison/storage
import gleamunison/sync
import gleamunison/sync_types.{PeerId}
import simplifile

const default_store = ".gleamunison/store.dets"

pub fn command(args: List(String)) -> Nil {
  case args {
    ["install", ..rest] -> install(rest)
    _ ->
      io.println(
        "usage: gleam run -- pkg install <manifest-hash> [--peer host:port] [--branch name]",
      )
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
