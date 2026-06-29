import gleam/dict.{type Dict}
import gleam/list
import gleam/result

pub type LogLevel {
  Debug
  Info
  Warn
  Error
}

pub type LogEntry {
  LogEntry(level: LogLevel, message: String, context: Dict(String, String))
}

@external(erlang, "gleamunison_log", "log_entry")
fn ffi_log_entry(
  level: String,
  message: String,
  context_keys: List(String),
  context_vals: List(String),
) -> Nil

fn level_to_string(level: LogLevel) -> String {
  case level {
    Debug -> "debug"
    Info -> "info"
    Warn -> "warn"
    Error -> "error"
  }
}

fn emit(
  level: LogLevel,
  message: String,
  context: Dict(String, String),
) -> Nil {
  let keys = dict.keys(context)
  let vals = list.map(keys, fn(k) { result.unwrap(dict.get(context, k), "") })
  ffi_log_entry(level_to_string(level), message, keys, vals)
}

pub fn debug(message: String) -> Nil {
  emit(Debug, message, dict.new())
}

pub fn info(message: String) -> Nil {
  emit(Info, message, dict.new())
}

pub fn warn(message: String) -> Nil {
  emit(Warn, message, dict.new())
}

pub fn error(message: String) -> Nil {
  emit(Error, message, dict.new())
}

pub fn debug_context(message: String, context: Dict(String, String)) -> Nil {
  emit(Debug, message, context)
}

pub fn info_context(message: String, context: Dict(String, String)) -> Nil {
  emit(Info, message, context)
}

pub fn warn_context(message: String, context: Dict(String, String)) -> Nil {
  emit(Warn, message, context)
}

pub fn error_context(message: String, context: Dict(String, String)) -> Nil {
  emit(Error, message, context)
}
