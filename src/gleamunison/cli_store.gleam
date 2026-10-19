//// A CLI owns its store handle: errors are data, and every completed
//// action closes before its result reaches the process-exit boundary.

import gleam/result
import gleam/string
import gleamunison/storage
import simplifile

pub fn with_dets(
  path: String,
  run: fn(storage.StorageAdapter) -> Result(a, String),
) -> Result(a, String) {
  use _ <- result.try(
    simplifile.create_directory_all(".gleamunison")
    |> result.map_error(fn(e) {
      "cannot create store directory: " <> string.inspect(e)
    }),
  )
  use adapter <- result.try(
    storage.dets(path)
    |> result.map_error(fn(e) {
      "cannot open store at " <> path <> ": " <> string.inspect(e)
    }),
  )
  let outcome = run(adapter)
  let closed = adapter.close()
  case outcome, closed {
    Error(reason), _ -> Error(reason)
    Ok(_), Error(reason) ->
      Error("cannot close store: " <> string.inspect(reason))
    Ok(value), Ok(_) -> Ok(value)
  }
}
