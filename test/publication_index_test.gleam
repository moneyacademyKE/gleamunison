//// The publication index has one owner, so these tests pin the three things
//// each command used to re-derive on its own: the on-disk bytes, the honest
//// read (missing = empty, unreadable = error), and the atomic replace that
//// leaves the previous index intact when a write fails.

import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleamunison/cli_result
import gleamunison/publication_index.{
  Entry, Failure, Opaque, Read, Replace, Write,
}
import gleeunit/should
import simplifile
import test_ffi.{unique_integer}

fn temp_path(label: String) -> String {
  "/tmp/gleamunison-index-" <> label <> "-" <> int.to_string(unique_integer())
}

pub fn the_index_bytes_round_trip_test() {
  let text = "alpha abc123\nbeta def456\n"
  text
  |> publication_index.parse
  |> publication_index.render
  |> should.equal(text)
}

/// An index with nothing in it is one newline byte, which is what publish,
/// unpublish and purge have all written when the last entry goes away.
pub fn an_empty_index_renders_as_a_single_newline_test() {
  publication_index.render([]) |> should.equal("\n")
}

pub fn a_missing_index_reads_as_empty_test() {
  publication_index.read(temp_path("missing")) |> should.equal(Ok([]))
}

/// publish flattened every read failure into an empty index, so a permission
/// error looked like a first publish and the rewrite dropped names the command
/// never managed to read. An unreadable index is a refusal, not "nothing here".
pub fn an_unreadable_index_is_an_error_not_an_empty_one_test() {
  let path = temp_path("unreadable")
  let assert Ok(_) = simplifile.create_directory_all(path)
  let result = publication_index.read(path)
  let assert Error(failure) = result
  failure.stage |> should.equal(Read)
  let assert Ok(_) = simplifile.delete(path)
  Nil
}

/// The guarantee the temp-and-rename buys: a write that cannot land leaves the
/// index a reader would still trust, not a truncated or half-written one.
pub fn a_failed_write_leaves_the_prior_index_intact_test() {
  let path = temp_path("failed-write")
  let before = "alpha abc123\n"
  let assert Ok(_) = simplifile.write(before, to: path)
  // Parking a directory where the temp file would go fails the write itself.
  let assert Ok(_) = simplifile.create_directory_all(path <> ".tmp")
  let result = publication_index.replace(path, [Entry("beta", "def456")])
  let assert Error(failure) = result
  failure.stage |> should.equal(Write)
  simplifile.read(path) |> should.equal(Ok(before))
  let assert Ok(_) = simplifile.delete(path)
  let assert Ok(_) = simplifile.delete(path <> ".tmp")
  Nil
}

/// A replace that cannot rename over the index must not leave the store with a
/// stray `.tmp` file: the next command reading that directory is not the one
/// that made the mess.
pub fn a_failed_replace_cleans_up_its_temp_file_test() {
  let path = temp_path("failed-replace")
  let assert Ok(_) = simplifile.create_directory_all(path)
  let result = publication_index.replace(path, [Entry("alpha", "abc123")])
  let assert Error(failure) = result
  failure.stage |> should.equal(Replace)
  simplifile.is_file(path <> ".tmp") |> should.equal(Ok(False))
  let assert Ok(_) = simplifile.delete(path)
  Nil
}

/// A line the format does not recognise is kept verbatim: a rewrite preserves
/// bytes it cannot interpret instead of silently dropping them.
pub fn a_rewrite_keeps_lines_it_cannot_parse_test() {
  let path = temp_path("opaque")
  let text = "alpha abc123\nnot-an-entry\nbeta def456\n"
  let assert Ok(_) = simplifile.write(text, to: path)
  let assert Ok(lines) = publication_index.read(path)
  list.contains(lines, Opaque("not-an-entry")) |> should.be_true
  let assert Ok(_) =
    publication_index.rewrite(path, lines, fn(name, _) { name != "alpha" })
  simplifile.read(path) |> should.equal(Ok("not-an-entry\nbeta def456\n"))
  let assert Ok(_) = simplifile.delete(path)
  Nil
}

/// Re-publishing a def moves its recorded hash and leaves the rest of the index
/// alone — kept lines first, then the new entries, exactly as before.
pub fn upsert_replaces_a_republished_name_and_keeps_the_rest_test() {
  let path = temp_path("upsert")
  let assert Ok(_) = simplifile.write("alpha old\nbeta keep\n", to: path)
  let assert Ok(lines) = publication_index.read(path)
  let assert Ok(_) =
    publication_index.upsert(path, lines, [
      Entry("alpha", "new"),
    ])
  simplifile.read(path) |> should.equal(Ok("beta keep\nalpha new\n"))
  let assert Ok(_) = simplifile.delete(path)
  Nil
}

pub fn hash_of_finds_only_the_published_name_test() {
  let lines = publication_index.parse("alpha abc123\nbeta def456\n")
  publication_index.hash_of(lines, "beta") |> should.equal(Some("def456"))
  publication_index.hash_of(lines, "gamma") |> should.equal(None)
}

/// unpublish and purge have always reported these three phrases, and publish
/// keeps its own (scripts/test_cli_truth.clj asserts it). Pinning the wording
/// here means a later refactor cannot silently reword a refusal.
pub fn describe_keeps_the_established_wording_test() {
  publication_index.describe("unpublish", Failure(Read, "Eacces"))
  |> should.equal(#(
    cli_result.refused,
    "unpublish: cannot read the index: Eacces",
  ))
  publication_index.describe("purge", Failure(Write, "Eisdir"))
  |> should.equal(#(cli_result.refused, "purge: cannot write the index: Eisdir"))
  publication_index.describe("unpublish", Failure(Replace, "Eexist"))
  |> should.equal(#(
    cli_result.refused,
    "unpublish: cannot replace the index: Eexist",
  ))
}
