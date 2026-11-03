//// The store-local publication index: one `name hash` line per published
//// subject, at the path `cli_lifecycle.manifest_path` hands out, terminated by
//// a newline. Published manifests are bytes other tooling reads, so this
//// module is the only parser, renderer and writer of that format — publish,
//// unpublish and purge all go through it and none of them re-derive the line
//// shape or the write dance.
////
//// Two rules each caller used to restate on its own:
////
//// - A MISSING index is an empty one (nothing published yet). Any other read
////   failure is an error: flattening it into an empty index let a rewrite
////   truncate content the command never managed to read.
//// - A rewrite goes through `<path>.tmp` and a rename, so a crash mid-write
////   leaves the previous index intact instead of half-written.

import gleam/list
import gleam/option.{type Option, from_result}
import gleam/string
import gleamunison/cli_result
import simplifile

/// One index line. `Opaque` is a non-empty line the format does not recognise;
/// a rewrite keeps it verbatim rather than dropping bytes it cannot interpret.
/// Blank lines carry no information and never survive `parse`.
pub type Line {
  Entry(name: String, hash: String)
  Opaque(text: String)
}

/// Which stage of an index operation failed.
pub type Stage {
  Read
  Write
  Replace
}

/// A failed stage plus the inspected filesystem error, so each command reports
/// the failure in its own established wording.
pub type Failure {
  Failure(stage: Stage, detail: String)
}

/// Parse index text into lines, dropping the blanks the trailing newline and any
/// empty line produce.
pub fn parse(content: String) -> List(Line) {
  content
  |> string.split("\n")
  |> list.filter_map(fn(line) {
    case line {
      "" -> Error(Nil)
      _ ->
        case string.split_once(line, " ") {
          Ok(#(name, hash)) -> Ok(Entry(name, hash))
          Error(_) -> Ok(Opaque(line))
        }
    }
  })
}

/// Render lines back to the exact on-disk shape. An empty index renders as a
/// lone newline, which is what every writer of this file has always produced.
pub fn render(lines: List(Line)) -> String {
  lines
  |> list.map(line_text)
  |> string.join("\n")
  <> "\n"
}

fn line_text(line: Line) -> String {
  case line {
    Entry(name, hash) -> name <> " " <> hash
    Opaque(text) -> text
  }
}

/// Read and parse the index. A missing file is an empty index; every other read
/// failure is reported instead of being flattened into "nothing published yet".
pub fn read(path: String) -> Result(List(Line), Failure) {
  case simplifile.read(path) {
    Ok(content) -> Ok(parse(content))
    Error(simplifile.Enoent) -> Ok([])
    Error(error) -> Error(Failure(Read, simplifile.describe_error(error)))
  }
}

/// The hash `name` is published under, if it is published at all.
pub fn hash_of(lines: List(Line), name: String) -> Option(String) {
  lines
  |> list.find_map(fn(line) {
    case line {
      Entry(found, hash) if found == name -> Ok(hash)
      _ -> Error(Nil)
    }
  })
  |> from_result
}

/// Rewrite the index keeping the entries `keep` accepts, by name and hash.
/// Lines the format does not recognise are always kept.
pub fn rewrite(
  path: String,
  lines: List(Line),
  keep: fn(String, String) -> Bool,
) -> Result(Nil, Failure) {
  let kept =
    list.filter(lines, fn(line) {
      case line {
        Entry(name, hash) -> keep(name, hash)
        Opaque(_) -> True
      }
    })
  replace(path, kept)
}

/// Replace the index with `entries` taking the place of any existing line for
/// the same name — publish's upsert, which is how re-publishing a def moves its
/// recorded hash without disturbing the rest of the index.
pub fn upsert(
  path: String,
  lines: List(Line),
  entries: List(Line),
) -> Result(Nil, Failure) {
  let names =
    entries
    |> list.filter_map(fn(entry) {
      case entry {
        Entry(name, _) -> Ok(name)
        Opaque(_) -> Error(Nil)
      }
    })
  let kept =
    list.filter(lines, fn(line) {
      case line {
        Entry(name, _) -> !list.contains(names, name)
        Opaque(_) -> True
      }
    })
  replace(path, list.append(kept, entries))
}

/// Write `lines` to the index atomically: content goes to `<path>.tmp` first and
/// is renamed into place, so a crash mid-write leaves the previous index intact.
/// A failed replace removes the temp file rather than leaving litter in a store.
pub fn replace(path: String, lines: List(Line)) -> Result(Nil, Failure) {
  let temp = path <> ".tmp"
  case simplifile.write(temp, render(lines)) {
    Error(error) -> Error(Failure(Write, simplifile.describe_error(error)))
    Ok(_) ->
      case simplifile.rename(temp, path) {
        Ok(_) -> Ok(Nil)
        Error(error) -> {
          let _ = simplifile.delete(temp)
          Error(Failure(Replace, simplifile.describe_error(error)))
        }
      }
  }
}

/// Render a failure in the wording the index commands have always used:
/// `<label>: cannot <stage> the index: <detail>`.
pub fn describe(label: String, failure: Failure) -> #(Int, String) {
  let stage = case failure.stage {
    Read -> "read"
    Write -> "write"
    Replace -> "replace"
  }
  #(
    cli_result.refused,
    label <> ": cannot " <> stage <> " the index: " <> failure.detail,
  )
}
