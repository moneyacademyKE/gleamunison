//// `gleamunison sync <peer> [--store path]` — pull definitions from a
//// peer over the sync protocol (BEAM distribution or host:port TCP).
//// Received chunks pass CAS acceptance: refs already held must match
//// byte-for-byte, and unsolicited chunks fail the transfer.

import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleamunison/codebase
import gleamunison/storage
import gleamunison/sync
import gleamunison/sync_types.{PeerId}

const default_store = ".gleamunison/store.dets"

pub fn command(args: List(String)) -> Nil {
  case parse_args(args, None, default_store) {
    Error(err) -> io.println("sync: " <> err)
    Ok(#(peer, store_path)) -> run_pull(peer, store_path)
  }
}

fn parse_args(
  args: List(String),
  peer: Option(String),
  store: String,
) -> Result(#(String, String), String) {
  case args {
    [] ->
      case peer {
        Some(p) -> Ok(#(p, store))
        None ->
          Error("usage: gleam run -- sync <peer-host:port> [--store path]")
      }
    ["--store", path, ..rest] -> parse_args(rest, peer, path)
    ["--store"] -> Error("--store needs a path")
    [arg, ..rest] ->
      case peer {
        None -> parse_args(rest, Some(arg), store)
        Some(_) -> Error("unknown argument: " <> arg)
      }
  }
}

fn run_pull(peer: String, store_path: String) -> Nil {
  case storage.dets(store_path) {
    Error(_) -> io.println("sync: cannot open store at " <> store_path)
    Ok(adapter) -> {
      let cb = codebase.with_adapter(adapter)
      let state = sync.new_sync_state()
      case sync.pull_sync(state, PeerId(peer), cb) {
        Ok(#(_, _, new_refs)) ->
          io.println(
            "sync: pulled "
            <> int.to_string(list.length(new_refs))
            <> " new definitions from "
            <> peer,
          )
        Error(err) -> io.println("sync: pull failed: " <> string.inspect(err))
      }
    }
  }
}
