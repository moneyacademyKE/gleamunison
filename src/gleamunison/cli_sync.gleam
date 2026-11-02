//// `gleamunison sync <peer> [--store path]` — pull definitions from a
//// peer over the sync protocol (BEAM distribution or host:port TCP).
//// Received chunks pass CAS acceptance: refs already held must match
//// byte-for-byte, and unsolicited chunks fail the transfer.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleamunison/cli_lifecycle
import gleamunison/cli_result
import gleamunison/cli_store
import gleamunison/codebase
import gleamunison/identity
import gleamunison/namespace
import gleamunison/storage
import gleamunison/store_log
import gleamunison/sync
import gleamunison/sync_types.{PeerId}

pub fn command(args: List(String)) -> Result(Nil, #(Int, String)) {
  use #(peer, store_override, branch) <- result.try(parse_args(
    args,
    None,
    None,
    None,
  ))
  use context <- result.try(
    cli_lifecycle.resolve_context(store_override)
    |> result.map_error(fn(message) { #(cli_result.unresolvable, message) }),
  )
  let store_path = cli_lifecycle.store_path(context)
  use output <- result.try(
    cli_store.with_dets(store_path, fn(adapter) {
      let cb = codebase.with_adapter(adapter)
      let state = sync.new_sync_state()
      use #(_, _, new_refs) <- result.try(
        sync.pull_sync(state, PeerId(peer), cb)
        |> result.map_error(fn(e) {
          "sync: pull failed: " <> sync.describe_error(e)
        }),
      )
      // Pulled content is admitted content: it entered this store just now, so
      // it belongs in the content log beside the definitions `publish` admits.
      list.each(new_refs, fn(ref) {
        let _ =
          store_log.record_content(
            cli_lifecycle.root_dir(context),
            identity.ref_hex(ref),
            "sync",
          )
        Nil
      })
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
    })
    |> result.map_error(fn(message) { #(cli_result.refused, message) }),
  )
  cli_result.success_coded(output)
}

fn parse_args(
  args: List(String),
  peer: Option(String),
  store: Option(String),
  branch: Option(String),
) -> Result(#(String, Option(String), Option(String)), #(Int, String)) {
  // Hand-rolled rather than cli_lifecycle.take_flag: here --branch is an
  // Option (absent means "do not pull a branch"), not a defaulted branch
  // name, so the shared FlagTail shape does not fit without contortion.
  // The missing-value wording and codes still come from cli_lifecycle.
  case args {
    [] ->
      case peer {
        Some(p) -> Ok(#(p, store, branch))
        None -> Error(#(cli_result.refused, usage()))
      }
    ["--store", path, ..rest] -> parse_args(rest, peer, Some(path), branch)
    ["--store"] -> Error(cli_lifecycle.missing_store_value(usage()))
    ["--branch", name, ..rest] -> parse_args(rest, peer, store, Some(name))
    ["--branch"] -> Error(cli_lifecycle.missing_branch_value(usage()))
    [arg, ..rest] ->
      case peer {
        None -> parse_args(rest, Some(arg), store, branch)
        Some(_) -> Error(#(cli_result.refused, "unknown argument: " <> arg))
      }
  }
}

fn usage() -> String {
  "usage: gleam run -- sync <peer-host:port> [--store path] [--branch name]"
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
