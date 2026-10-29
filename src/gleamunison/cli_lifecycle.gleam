//// Where a store lives, and whether a run trusts it.
////
//// Two decisions belong here rather than scattered across commands: the store
//// directory (an override for tests, CI, and running an artifact from
//// anywhere) and whether unverified content may execute. Both are environment
//// reads, so both are resolved in one place and passed in as data.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

@external(erlang, "gleamunison_config", "get_env")
fn get_env(key: String) -> Result(String, Nil)

const default_dir = ".gleamunison"

const store_file = "store.dets"

const manifest_file = "published"

pub type StoreContext {
  StoreContext(store_path: String, manifest_path: String, root_dir: String)
}

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
    Ok(dir) -> validate_store_dir(dir)
  }
}

/// Resolve all sibling paths from one selected store file. Commands with a
/// `--store` flag pass that path here; other commands pass `None` and use the
/// environment/default directory. The context keeps DETS, manifests, and logs
/// on one boundary instead of letting each command choose a root independently.
pub fn resolve_context(
  store_override: Option(String),
) -> Result(StoreContext, String) {
  let selected = case store_override {
    Some(path) -> validate_store_path(path)
    None ->
      resolve_store_dir()
      |> result.map(store_file_path)
  }
  use store_path <- result.try(selected)
  let root_dir = directory_of(store_path)
  Ok(StoreContext(
    store_path: store_path,
    manifest_path: join(root_dir, manifest_file),
    root_dir: root_dir,
  ))
}

/// The store file inside the environment-resolved directory.
pub fn resolve_store_path() -> Result(String, String) {
  resolve_context(None) |> result.map(fn(context) { context.store_path })
}

pub fn store_path(context: StoreContext) -> String {
  context.store_path
}

pub fn manifest_path(context: StoreContext) -> String {
  context.manifest_path
}

pub fn root_dir(context: StoreContext) -> String {
  context.root_dir
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

fn validate_store_dir(path: String) -> Result(String, String) {
  case string.starts_with(path, "/") {
    True -> Ok(path)
    False ->
      Error("GLEAMUNISON_STORE_DIR must be an absolute path, got: " <> path)
  }
}

fn validate_store_path(path: String) -> Result(String, String) {
  case string.starts_with(path, "/") {
    True -> Ok(path)
    False -> Error("store path must be absolute, got: " <> path)
  }
}

fn store_file_path(dir: String) -> String {
  join(dir, store_file)
}

fn join(dir: String, file: String) -> String {
  case string.ends_with(dir, "/") {
    True -> dir <> file
    False -> dir <> "/" <> file
  }
}

fn directory_of(path: String) -> String {
  case string.split(path, "/") |> list.reverse {
    [_, ..parent] ->
      case list.reverse(parent) |> string.join("/") {
        "" -> "/"
        dir -> dir
      }
    [] -> "."
  }
}
