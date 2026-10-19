//// `gleamunison sync <peer> [--store path]` — pull definitions from a
//// peer over the sync protocol (BEAM distribution or host:port TCP).
//// Received chunks pass CAS acceptance: refs already held must match
//// byte-for-byte, and unsolicited chunks fail the transfer.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleamunison/cli_result
import gleamunison/cli_store
import gleamunison/codebase
import gleamunison/namespace
import gleamunison/storage
import gleamunison/sync
import gleamunison/sync_types.{PeerId}

const default_store = ".gleamunison/store.dets"

pub fn command(args: List(String)) -> Result(Nil, String) {
  use #(peer, store_path, branch) <- result.try(parse_args(
    args,
    None,
    default_store,
    None,
  ))
  use output <- result.try(
    cli_store.with_dets(store_path, fn(adapter) {
      let cb = codebase.with_adapter(adapter)
      let state = sync.new_sync_state()
      use #(_, _, new_refs) <- result.try(
        sync.pull_sync(state, PeerId(peer), cb)
        |> result.map_error(fn(e) { "sync: pull failed: " <> string.inspect(e) }),
      )
      use _ <- result.try(case branch {
        None -> Ok(Nil)
        Some(name) -> pull_branch(peer, name, adapter)
      })
      let branch_status = case branch {
        None -> ""
        Some(name) -> "; branch " <> name <> " pulled and verified"
      }
      Ok(
        "sync: pulled "
        <> int.to_string(list.length(new_refs))
        <> " new definitions from "
        <> peer
        <> branch_status,
      )
    }),
  )
  cli_result.success(output)
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

/// Pull a branch's chunk set: the pointer ref is derivable from the branch
/// name, each head chunk names its namespace and predecessor. Walk until
/// the chain ends, then import the whole set (import verifies integrity).
fn pull_branch(
  peer: String,
  branch: String,
  adapter: storage.StorageAdapter,
) -> Result(Nil, String) {
  use chunks <- result.try(
    fetch_branch_chunks(peer, branch, [namespace.pointer_ref_hex(branch)], []),
  )
  namespace.import_branch(adapter, chunks)
  |> result.map_error(fn(e) { "sync: branch import failed: " <> e })
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
                  use #(self_hex, ns_hex, prev) <- result.try(
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
