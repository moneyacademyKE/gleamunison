//// A CLI owns its store handle: errors are data, and every completed
//// action closes before its result reaches the process-exit boundary.

import gleam/list
import gleam/result
import gleam/string
import gleamunison/storage
import simplifile

/// Open a store, run the action, close the store. Errors carry a String.
pub fn with_dets(
  path: String,
  run: fn(storage.StorageAdapter) -> Result(a, String),
) -> Result(a, String) {
  with_dets_mapped(path, run, fn(message) { message })
}

/// Same lifecycle for a caller whose error type is richer than String — a CLI
/// whose exit code is part of the contract, for instance. `on_store_error`
/// lifts the store's own failures into that type so one channel carries every
/// failure.
pub fn with_dets_mapped(
  path: String,
  run: fn(storage.StorageAdapter) -> Result(a, e),
  on_store_error: fn(String) -> e,
) -> Result(a, e) {
  use _ <- result.try(
    simplifile.create_directory_all(directory_of(path))
    |> result.map_error(fn(e) {
      on_store_error("cannot create store directory: " <> string.inspect(e))
    }),
  )
  use adapter <- result.try(
    storage.dets(path)
    |> result.map_error(fn(e) {
      on_store_error(
        "cannot open store at " <> path <> ": " <> string.inspect(e),
      )
    }),
  )
  let outcome = run(adapter)
  let closed = adapter.close()
  case outcome, closed {
    Error(reason), _ -> Error(reason)
    Ok(_), Error(reason) ->
      Error(on_store_error("cannot close store: " <> string.inspect(reason)))
    Ok(value), Ok(_) -> Ok(value)
  }
}

/// The directory a store file lives in, derived from the path so an overridden
/// store does not also create the default `.gleamunison` in the working
/// directory. A bare filename lives in the current directory.
fn directory_of(path: String) -> String {
  case list.reverse(string.split(path, "/")) {
    [_, ..reversed_parent] ->
      case list.reverse(reversed_parent) |> string.join("/") {
        "" -> "/"
        dir -> dir
      }
    [] -> "."
  }
}
