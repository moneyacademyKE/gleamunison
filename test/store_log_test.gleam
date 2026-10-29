//// The store's own logs: what entered it, what was run. Append-only, durable
//// across restarts (dets beside the store file), and readable in insertion
//// order. The tail is the last N, oldest first.

import gleamunison/datetime
import gleamunison/store_log
import gleeunit/should
import simplifile

fn temp_dir(name: String) -> String {
  let dir = "/tmp/gleamunison-store-log-test-" <> name
  let _ = simplifile.delete_all([dir])
  let assert Ok(_) = simplifile.create_directory_all(dir)
  dir
}

pub fn a_content_entry_round_trips_test() {
  // The timestamp is "now", which a test cannot pin: the parts the test
  // controls are the ref and the kind.
  let dir = temp_dir("content-round-trip")
  store_log.record_content(dir, "aaaa", "term") |> should.equal(Ok(Nil))
  let assert Ok(entries) = store_log.content_tail(dir, 10)
  case entries {
    [entry] -> {
      entry.ref_hex |> should.equal("aaaa")
      entry.kind |> should.equal("term")
    }
    _ -> should.fail()
  }
}

pub fn entries_are_oldest_first_test() {
  let dir = temp_dir("content-order")
  store_log.record_content(dir, "first", "term") |> should.equal(Ok(Nil))
  store_log.record_content(dir, "second", "term") |> should.equal(Ok(Nil))
  store_log.record_content(dir, "third", "term") |> should.equal(Ok(Nil))
  let assert Ok(entries) = store_log.content_tail(dir, 10)
  refs(entries) |> should.equal(["first", "second", "third"])
}

pub fn the_tail_keeps_the_newest_test() {
  let dir = temp_dir("content-tail")
  store_log.record_content(dir, "one", "term") |> should.equal(Ok(Nil))
  store_log.record_content(dir, "two", "term") |> should.equal(Ok(Nil))
  store_log.record_content(dir, "three", "term") |> should.equal(Ok(Nil))
  let assert Ok(entries) = store_log.content_tail(dir, 2)
  refs(entries) |> should.equal(["two", "three"])
}

pub fn an_empty_log_is_empty_not_an_error_test() {
  let dir = temp_dir("content-empty")
  store_log.content_tail(dir, 5) |> should.equal(Ok([]))
  store_log.exec_tail(dir, 5) |> should.equal(Ok([]))
}

pub fn an_execution_entry_carries_its_outcome_and_reason_test() {
  let dir = temp_dir("exec-entry")
  store_log.record_exec(dir, "bbbb", "refused", "wrong arity", "cli")
  |> should.equal(Ok(Nil))
  let assert Ok(entries) = store_log.exec_tail(dir, 5)
  case entries {
    [entry] -> {
      entry.ref_hex |> should.equal("bbbb")
      entry.outcome |> should.equal("refused")
      entry.reason |> should.equal("wrong arity")
    }
    _ -> should.fail()
  }
}

pub fn the_two_logs_are_separate_test() {
  let dir = temp_dir("two-logs")
  store_log.record_content(dir, "content-ref", "term") |> should.equal(Ok(Nil))
  store_log.record_exec(dir, "exec-ref", "ok", "", "cli")
  |> should.equal(Ok(Nil))
  let assert Ok(content) = store_log.content_tail(dir, 5)
  let assert Ok(exec) = store_log.exec_tail(dir, 5)
  refs(content) |> should.equal(["content-ref"])
  exec_refs(exec) |> should.equal(["exec-ref"])
}

pub fn entries_are_time_ordered_and_timestamped_test() {
  let dir = temp_dir("timestamps")
  let before = datetime.now_unix()
  store_log.record_content(dir, "stamped", "term") |> should.equal(Ok(Nil))
  let after = datetime.now_unix()
  let assert Ok(entries) = store_log.content_tail(dir, 5)
  case entries {
    [entry] -> {
      { entry.at >= before } |> should.be_true
      { entry.at <= after } |> should.be_true
    }
    _ -> should.fail()
  }
}

fn refs(entries: List(store_log.ContentEntry)) -> List(String) {
  case entries {
    [] -> []
    [first, ..rest] -> [first.ref_hex, ..refs(rest)]
  }
}

fn exec_refs(entries: List(store_log.ExecEntry)) -> List(String) {
  case entries {
    [] -> []
    [first, ..rest] -> [first.ref_hex, ..exec_refs(rest)]
  }
}

pub fn the_merged_view_orders_both_logs_by_time_test() {
  let dir = temp_dir("merged-order")
  store_log.record_content(dir, "content-ref", "term") |> should.equal(Ok(Nil))
  store_log.record_exec(dir, "exec-ref", "ok", "", "cli")
  |> should.equal(Ok(Nil))
  let assert Ok(rows) = store_log.merged_tail(dir, 10)
  merged_kinds(rows) |> should.equal(["content", "exec"])
}

pub fn the_merged_view_carries_the_label_and_detail_test() {
  let dir = temp_dir("merged-detail")
  store_log.record_exec(dir, "cccc", "refused", "wrong arity", "cli")
  |> should.equal(Ok(Nil))
  let assert Ok(rows) = store_log.merged_tail(dir, 10)
  case rows {
    [row] -> {
      row.kind |> should.equal("exec")
      row.label |> should.equal("refused")
      row.detail |> should.equal("wrong arity")
    }
    _ -> should.fail()
  }
}

pub fn an_execution_entry_carries_its_caller_test() {
  let dir = temp_dir("exec-caller")
  store_log.record_exec(dir, "dddd", "ok", "", "cli") |> should.equal(Ok(Nil))
  let assert Ok(entries) = store_log.exec_tail(dir, 5)
  case entries {
    [entry] -> entry.caller |> should.equal("cli")
    _ -> should.fail()
  }
}

fn merged_kinds(rows: List(store_log.MergedEntry)) -> List(String) {
  case rows {
    [] -> []
    [first, ..rest] -> [first.kind, ..merged_kinds(rest)]
  }
}
