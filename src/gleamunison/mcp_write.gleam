//// MCP write admission and the supervised owner RPC. No storage key, branch,
//// or store path crosses this boundary.

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/result
import gleamunison/env
import gleamunison/mcp.{type Tool, Tool}
import gleamunison/sandbox_policy

@external(erlang, "gleamunison_web_session", "publish")
fn owner_publish(source: String) -> Result(String, String)

pub fn tool() -> Tool {
  Tool(
    name: "agent_publish",
    description: "Test, attest, and publish source on the server-selected branch; returns runnable content refs",
    handler: publish_arguments,
  )
}

pub fn check_writable() -> Result(Nil, String) {
  let profile = env.string_or("GLEAMUNISON_PROFILE", "local")
  case sandbox_policy.denies_untrusted_execution(profile) {
    True -> Error("agent_publish_refused: untrusted profile cannot write")
    False -> Ok(Nil)
  }
}

pub fn publish(source: String) -> Result(String, String) {
  use _ <- result.try(check_writable())
  owner_publish(source)
}

fn publish_arguments(args: Dict(String, Dynamic)) -> Result(String, String) {
  case dict.get(args, "source") {
    Error(_) -> Error("missing string argument: source")
    Ok(value) ->
      case decode.run(value, decode.string) {
        Error(_) -> Error("missing string argument: source")
        Ok(source) -> publish(source)
      }
  }
}
