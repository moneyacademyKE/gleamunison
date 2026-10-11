//// MCP server lifecycle: boots a session process that the HTTP `/mcp`
//// route talks to. The session is immutable after boot (eval is read-only),
//// so the process never mutates — it exists so concurrent request processes
//// can reach one booted session by name.

@external(erlang, "gleamunison_mcp_session", "start")
fn ffi_start(load_files: List(String)) -> Result(Nil, String)

@external(erlang, "gleamunison_mcp_session", "stop")
fn ffi_stop() -> Nil

/// Boot the MCP session process, optionally loading lisp source files
/// (defines only take effect through the same pipeline `verify` uses).
pub fn start(load_files: List(String)) -> Result(Nil, String) {
  ffi_start(load_files)
}

pub fn stop() -> Nil {
  ffi_stop()
}
