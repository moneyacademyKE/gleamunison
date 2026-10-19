//// `gleamunison sync <peer> [--store path]` — pull definitions from a
//// peer over the sync protocol (BEAM distribution or host:port TCP).
//// Received chunks pass CAS acceptance: refs already held must match
//// byte-for-byte, and unsolicited chunks fail the transfer.

import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleamunison/cli_result
import gleamunison/codebase
import gleamunison/namespace
import gleamunison/storage
import gleamunison/sync
import gleamunison/sync_types.{PeerId}

const default_store = ".gleamunison/store.dets"

pub fn command(args: List(String)) -> Nil {
  case parse_args(args, None, default_store, None) {
    Error(err) -> io.println("sync: " <> err)
    Ok(#(peer, store_path, branch)) -> run_pull(peer, store_path, branch)
  }
}

fn parse_args(
  args: List(String),
  peer: Option(String),
  store: String,
  branch: Option(String),
) -> Result(#(String, String, Option(String)), String) {
  case args {
    [] ->
      case peer {
        Some(p) -> Ok(#(p, store, branch))
        None ->
          Error(
            "usage: gleam run -- sync <peer-host:port> [--store path] [--branch name]",
          )
      }
    ["--store", path, ..rest] -> parse_args(rest, peer, path, branch)
    ["--store"] -> Error("--store needs a path")
    ["--branch", name, ..rest] -> parse_args(rest, peer, store, Some(name))
    ["--branch"] -> Error("--branch needs a name")
    [arg, ..rest] ->
      case peer {
        None -> parse_args(rest, Some(arg), store, branch)
        Some(_) -> Error("unknown argument: " <> arg)
      }
  }
}

fn run_pull(peer: String, store_path: String, branch: Option(String)) -> Nil {
  case storage.dets(store_path) {
    Error(_) -> io.println("sync: cannot open store at " <> store_path)
    Ok(adapter) -> {
      let cb = codebase.with_adapter(adapter)
      let state = sync.new_sync_state()
      case sync.pull_sync(state, PeerId(peer), cb) {
        Ok(#(_, _, new_refs)) -> {
          io.println(
            "sync: pulled "
            <> int.to_string(list.length(new_refs))
            <> " new definitions from "
            <> peer,
          )
          case branch {
            None -> Nil
            Some(name) -> pull_branch(peer, name, adapter)
          }
        }
        Error(err) ->
          cli_result.fail("sync: pull failed: " <> string.inspect(err))
      }
    }
  }
}

/// Pull a branch's chunk set: the pointer ref is derivable from the branch
/// name, each head chunk names its namespace and predecessor. Walk until
/// the chain ends, then import the whole set (import verifies integrity).
fn pull_branch(
  peer: String,
  branch: String,
  adapter: storage.StorageAdapter,
) -> Nil {
  case
    fetch_branch_chunks(peer, branch, [namespace.pointer_ref_hex(branch)], [])
  {
    Error(err) -> io.println("sync: branch " <> branch <> ": " <> err)
    Ok(chunks) ->
      case namespace.import_branch(adapter, chunks) {
        Ok(_) -> io.println("sync: branch " <> branch <> " pulled and verified")
        Error(err) -> io.println("sync: branch import failed: " <> err)
      }
  }
}

fn fetch_branch_chunks(
  peer: String,
  branch: String,
  pending: List(String),
  acc: List(#(String, BitArray)),
) -> Result(List(#(String, BitArray)), String) {
  case pending {
    [] -> Ok(list.reverse(acc))
    [hex, ..rest] ->
      case list.any(acc, fn(pair) { pair.0 == hex }) {
        True -> fetch_branch_chunks(peer, branch, rest, acc)
        False ->
          case sync_types.sync_request_defs(peer, [hex]) {
            Error(e) -> Error("fetch failed for " <> hex <> ": " <> e)
            Ok([]) -> Error("peer has no chunk " <> hex)
            Ok([#(_, bytes), ..]) -> {
              let is_pointer = hex == namespace.pointer_ref_hex(branch)
              case is_pointer {
                True -> {
                  use #(self_hex, ns_hex, prev) <- result_try(
                    namespace.parse_head_hexes(bytes),
                  )
                  let next =
                    list.flatten([
                      rest,
                      [ns_hex],
                      case prev {
                        Some(p) -> [p]
                        None -> []
                      },
                    ])
                  fetch_branch_chunks(peer, branch, next, [
                    #("pointer:" <> branch, bytes),
                    #("chunk:" <> self_hex, bytes),
                    ..acc
                  ])
                }
                False ->
                  fetch_branch_chunks(peer, branch, rest, [
                    #("chunk:" <> hex, bytes),
                    ..acc
                  ])
              }
            }
          }
      }
  }
}

fn result_try(
  r: Result(a, String),
  f: fn(a) -> Result(b, String),
) -> Result(b, String) {
  case r {
    Ok(v) -> f(v)
    Error(e) -> Error(e)
  }
}
