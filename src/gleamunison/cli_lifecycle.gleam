//// Where a store lives, and whether a run trusts it.
////
//// Two decisions belong here rather than scattered across commands: the store
//// directory (an override for tests, CI, and running an artifact from
//// anywhere) and whether unverified content may execute. Both are environment
//// reads, so both are resolved in one place and passed in as data.

import gleam/result
import gleam/string

@external(erlang, "gleamunison_config", "get_env")
fn get_env(key: String) -> Result(String, Nil)

const default_dir = ".gleamunison"

const store_file = "store.dets"

pub fn default_store_dir() -> String {
  default_dir
}

/// The store directory: GLEAMUNISON_STORE_DIR when set, else `.gleamunison`.
/// A relative override is refused rather than guessed at — a store resolved
/// against the wrong working directory looks empty, and an empty store reads
/// as "your definition was never published".
pub fn resolve_store_dir() -> Result(String, String) {
  case get_env("GLEAMUNISON_STORE_DIR") {
    Error(_) -> Ok(default_dir)
    Ok(dir) if dir == "" -> Ok(default_dir)
    Ok(dir) ->
      case string.starts_with(dir, "/") {
        True -> Ok(dir)
        False ->
          Error("GLEAMUNISON_STORE_DIR must be an absolute path, got: " <> dir)
      }
  }
}

/// The store file inside the resolved directory.
pub fn resolve_store_path() -> Result(String, String) {
  use dir <- result.try(resolve_store_dir())
  case string.ends_with(dir, "/") {
    True -> Ok(dir <> store_file)
    False -> Ok(dir <> "/" <> store_file)
  }
}

/// The escape hatch: GLEAMUNISON_STORE_ALLOW_UNVERIFIED=1 lets a run execute
/// content whose evidence does not verify. Absent means verify.
pub fn resolve_allow_unverified() -> Bool {
  case get_env("GLEAMUNISON_STORE_ALLOW_UNVERIFIED") {
    Ok(value) ->
      case string.lowercase(value) {
        "1" -> True
        "true" -> True
        "yes" -> True
        _ -> False
      }
    Error(_) -> False
  }
}

const manifest_file = "published"

/// The name → hash index, beside the store. Derived from the store directory
/// so an overridden store never writes its manifest into the default one.
pub fn resolve_manifest_path() -> Result(String, String) {
  use dir <- result.try(resolve_store_dir())
  case string.ends_with(dir, "/") {
    True -> Ok(dir <> manifest_file)
    False -> Ok(dir <> "/" <> manifest_file)
  }
}
