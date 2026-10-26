//// Serialize publication and snapshot replacement in the web-session owner.

import gleam/option.{None}
import gleam/result
import gleamunison/active_storage
import gleamunison/agent_publish
import gleamunison/cli_lifecycle
import gleamunison/mcp_session.{type SessionState}
import gleamunison/mcp_write

pub fn publish(
  previous: SessionState,
  source: String,
) -> Result(#(String, SessionState), String) {
  use _ <- result.try(mcp_write.check_writable())
  use context <- result.try(cli_lifecycle.resolve_context(None))
  use adapter <- result.try(active_storage.active_or_open())
  use publication <- result.try(agent_publish.publish_source(
    adapter,
    source,
    mcp_session.selected_branch(),
    False,
    cli_lifecycle.root_dir(context),
  ))
  use fresh <- result.try(mcp_session.boot_configured())
  Ok(#(
    agent_publish.json(publication),
    mcp_session.overlay_scratch(fresh, previous),
  ))
}
