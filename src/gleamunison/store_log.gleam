//// The store's own record of what happened to it.
////
//// Two append-only logs beside the store file, each keyed by a monotonic
//// sequence number: `content` (what entered the store) and `exec` (what was
//// run, and how it ended). They are separate from the store because the store
//// is content-addressed and immutable, while a log is time-ordered: writing a
//// changing fact into the store would put it behind a hash that cannot change.
////
//// The logs are store-owned. Any command that admits or executes a definition
//// writes to them, so the record does not depend on which CLI path ran.

import gleam/list
import gleamunison/datetime

pub type ContentEntry {
  ContentEntry(ref_hex: String, kind: String, at: Int)
}

pub type ExecEntry {
  ExecEntry(
    ref_hex: String,
    outcome: String,
    reason: String,
    caller: String,
    at: Int,
  )
}

/// One row of the merged view: either kind of entry, in chronological order.
pub type MergedEntry {
  MergedEntry(
    kind: String,
    ref_hex: String,
    label: String,
    detail: String,
    at: Int,
  )
}

@external(erlang, "gleamunison_store_log", "append_content")
fn append_content_ffi(
  dir: String,
  ref_hex: String,
  kind: String,
  at: Int,
) -> Result(Int, String)

@external(erlang, "gleamunison_store_log", "tail_content")
fn tail_content_ffi(
  dir: String,
  n: Int,
) -> Result(List(#(String, String, Int)), String)

@external(erlang, "gleamunison_store_log", "append_exec")
fn append_exec_ffi(
  dir: String,
  ref_hex: String,
  outcome: String,
  reason: String,
  caller: String,
  at: Int,
) -> Result(Int, String)

@external(erlang, "gleamunison_store_log", "merged_tail")
fn merged_tail_ffi(
  dir: String,
  n: Int,
) -> Result(List(#(String, String, String, String, Int)), String)

@external(erlang, "gleamunison_store_log", "tail_exec")
fn tail_exec_ffi(
  dir: String,
  n: Int,
) -> Result(List(#(String, String, String, String, Int)), String)

/// Record that a definition entered the store. Failure is returned, never
/// swallowed: a store that cannot say what it holds is a store you cannot
/// audit.
pub fn record_content(
  dir: String,
  ref_hex: String,
  kind: String,
) -> Result(Nil, String) {
  append_content_ffi(dir, ref_hex, kind, datetime.now_unix())
  |> result_map_nil
}

/// Record one execution attempt: outcome is "ok" or "refused", reason names
/// why when it is not "ok".
pub fn record_exec(
  dir: String,
  ref_hex: String,
  outcome: String,
  reason: String,
  caller: String,
) -> Result(Nil, String) {
  append_exec_ffi(dir, ref_hex, outcome, reason, caller, datetime.now_unix())
  |> result_map_nil
}

pub fn content_tail(dir: String, n: Int) -> Result(List(ContentEntry), String) {
  tail_content_ffi(dir, n)
  |> map_result(fn(rows) {
    list.map(rows, fn(row) {
      ContentEntry(ref_hex: row.0, kind: row.1, at: row.2)
    })
  })
}

pub fn exec_tail(dir: String, n: Int) -> Result(List(ExecEntry), String) {
  tail_exec_ffi(dir, n)
  |> map_result(fn(rows) {
    list.map(rows, fn(row) {
      ExecEntry(
        ref_hex: row.0,
        outcome: row.1,
        reason: row.2,
        caller: row.3,
        at: row.4,
      )
    })
  })
}

/// Both logs as one chronological view. Every row carries its kind, so a reader
/// can tell an admission from an execution without consulting two commands.
pub fn merged_tail(dir: String, n: Int) -> Result(List(MergedEntry), String) {
  merged_tail_ffi(dir, n)
  |> map_result(fn(rows) {
    list.map(rows, fn(row) {
      MergedEntry(
        kind: row.0,
        ref_hex: row.1,
        label: row.2,
        detail: row.3,
        at: row.4,
      )
    })
  })
}

fn result_map_nil(result: Result(a, String)) -> Result(Nil, String) {
  case result {
    Ok(_) -> Ok(Nil)
    Error(reason) -> Error(reason)
  }
}

fn map_result(result: Result(a, String), fun: fn(a) -> b) -> Result(b, String) {
  case result {
    Ok(value) -> Ok(fun(value))
    Error(reason) -> Error(reason)
  }
}
