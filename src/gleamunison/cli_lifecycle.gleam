//// Where a store lives, whether a run trusts it, and which branch it reads.
////
//// Three decisions belong here rather than scattered across commands: the
//// store directory (an override for tests, CI, and running an artifact from
//// anywhere), whether unverified content may execute, and which branch a
//// session or command is bound to. All three are resolved through the live
//// configuration layer and passed in as data.

import filepath
import gleam/option.{type Option, None, Some}
import gleam/result
import gleamunison/cli_result
import gleamunison/config.{type Config}

const default_dir = ".gleamunison"

const store_file = "store.dets"

const manifest_file = "published"

/// The branch a store-scoped command runs against when `--branch` is absent.
/// The commands that peel `--store`/`--branch` take their default from here
/// instead of declaring their own "main", so the default cannot drift between
/// them.
///
/// Two look-alikes deliberately stay where they are: `cli_publish.publish_branch`
/// is where publish records its entries — a decision of its own that happens to
/// share the name — and `run_ref.default_branch` is public surface the
/// branch-scope tests read.
pub const default_branch = "main"

pub type StoreContext {
  StoreContext(store_path: String, manifest_path: String, root_dir: String)
}

pub fn default_store_dir() -> String {
  default_dir
}

/// The store directory: `GLEAMUNISON_STORE_DIR` when set, else `.gleamunison`.
/// A relative override is refused rather than guessed at — a store resolved
/// against the wrong working directory looks empty, and an empty store reads
/// as "your definition was never published".
pub fn resolve_store_dir() -> Result(String, String) {
  use cfg <- result.try(config.load())
  store_dir_from(cfg)
}

fn store_dir_from(cfg: Config) -> Result(String, String) {
  use value <- result.try(config.optional_string(cfg, "GLEAMUNISON_STORE_DIR"))
  case value {
    None -> Ok(default_dir)
    Some("") -> Ok(default_dir)
    Some(dir) -> validate_store_dir(dir)
  }
}

/// Resolve all sibling paths from one selected store file. Commands with a
/// `--store` flag pass that path here; other commands pass `None` and use the
/// configured/default directory. The context keeps DETS, manifests, and logs
/// on one boundary instead of letting each command choose a root independently.
pub fn resolve_context(
  store_override: Option(String),
) -> Result(StoreContext, String) {
  use cfg <- result.try(config.load())
  let selected = case store_override {
    Some(path) -> validate_store_path(path)
    None ->
      store_dir_from(cfg)
      |> result.map(store_file_path)
  }
  use store_path <- result.try(selected)
  let root_dir = filepath.directory_name(store_path)
  Ok(StoreContext(
    store_path: store_path,
    manifest_path: filepath.join(root_dir, manifest_file),
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

/// The escape hatch: `GLEAMUNISON_STORE_ALLOW_UNVERIFIED=1` lets a run execute
/// content whose evidence does not verify. Absent means verify; a malformed
/// configuration is an error rather than a silent default.
pub fn resolve_allow_unverified() -> Result(Bool, String) {
  use cfg <- result.try(config.load())
  config.flag(cfg, "GLEAMUNISON_STORE_ALLOW_UNVERIFIED")
}

/// The branch a session or command is bound to: `GLEAMUNISON_BRANCH` through
/// the CLI > TOML > env precedence, else `default_branch`. This lived in
/// mcp_session, which made the refresh path and the hand-written HTTP routes
/// depend on a 443-line session module for a pure configuration decision.
pub fn resolve_branch() -> Result(String, String) {
  use cfg <- result.try(config.load())
  branch_from(cfg)
}

fn branch_from(cfg: Config) -> Result(String, String) {
  config.string_or(cfg, "GLEAMUNISON_BRANCH", default_branch)
}

/// `--store` given with no path after it. purge and unpublish refuse with
/// exactly these bytes and this exit code, so the wording lives here rather
/// than in two files that could drift apart.
///
/// cli_run delegates its tail spelling to take_flag below but keeps its own
/// missing-value bytes, because its errors carry the "run: " prefix users
/// have always seen. pkg's publish subcommand has its own --name/--version
/// grammar, and sync's --branch is an Option (absent means "pull no branch")
/// rather than a defaulted name. Folding those in would mean parameterising
/// the message, the error type and the precedence: more machinery than the
/// four lines it would save.
pub fn missing_store_value(usage: String) -> #(Int, String) {
  #(cli_result.refused, "--store needs a path\n" <> usage)
}

/// `--branch` given with no name after it. Same two commands, same exceptions.
pub fn missing_branch_value(usage: String) -> #(Int, String) {
  #(cli_result.refused, "--branch needs a name\n" <> usage)
}

/// The `--store`/`--branch` tail every store-scoped command shares, as data.
/// `branch` is a plain accumulator with the caller's default already in it,
/// so a command needs exactly one parser no matter where `--branch` appears
/// — cli_pkg used to grow a second parser (`parse_args_with_branch`) solely
/// because branch was kept out of the accumulator, and that second parser
/// then forgot flags the first one knew.
pub type FlagTail {
  FlagTail(store: Option(String), branch: String)
}

pub fn flag_tail(default_branch: String) -> FlagTail {
  FlagTail(store: None, branch: default_branch)
}

/// What the head of an argument list is, to the shared tail.
pub type FlagTake {
  /// A `--store`/`--branch` flag and its value were consumed.
  Taken(tail: FlagTail, rest: List(String))
  /// One of those flags is present but its value is missing. The caller
  /// builds the error from its own usage() via missing_store_value /
  /// missing_branch_value above, so wording and exit code stay owned here.
  MissingValue(flag: String)
  /// The head is something else: a positional, a command's own flag, or an
  /// unknown argument. The caller decides which.
  NotTailFlag
}

/// Consume one `--store`/`--branch` flag (with its value) from the head of
/// `args`. This owns the spelling of the shared tail; each command keeps its
/// own positionals and extra flags, which is why grammars that genuinely
/// differ (cli_find's multi-word query) stay hand-rolled.
pub fn take_flag(args: List(String), tail: FlagTail) -> FlagTake {
  case args {
    ["--store", path, ..rest] ->
      Taken(FlagTail(..tail, store: Some(path)), rest)
    ["--store"] -> MissingValue("--store")
    ["--branch", name, ..rest] -> Taken(FlagTail(..tail, branch: name), rest)
    ["--branch"] -> MissingValue("--branch")
    _ -> NotTailFlag
  }
}

fn validate_store_dir(path: String) -> Result(String, String) {
  case filepath.is_absolute(path) {
    True -> Ok(path)
    False ->
      Error("GLEAMUNISON_STORE_DIR must be an absolute path, got: " <> path)
  }
}

fn validate_store_path(path: String) -> Result(String, String) {
  case filepath.is_absolute(path) {
    True -> Ok(path)
    False -> Error("store path must be absolute, got: " <> path)
  }
}

fn store_file_path(dir: String) -> String {
  filepath.join(dir, store_file)
}
