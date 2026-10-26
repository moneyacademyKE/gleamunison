//// agent_generate: bounded model output through the supervised admitted write.
//// The tool input contains no storage, branch, credential, or provider control.

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/result
import gleamunison/generation_loop
import gleamunison/generation_request
import gleamunison/mcp.{type Tool, Tool}
import gleamunison/mcp_write

@external(erlang, "gleamunison_web_session", "generate")
fn owner_generate(plan: generation_loop.Plan) -> Result(String, String)

pub fn tool() -> Tool {
  Tool(
    name: "agent_generate",
    description: "Generate, repair, test, attest, and publish one signature-typed term; server-owned provider and bounded attempts",
    handler: generate,
  )
}

pub fn generate(args: Dict(String, Dynamic)) -> Result(String, String) {
  use _ <- result.try(mcp_write.check_writable())
  use plan <- result.try(generation_request.plan(args))
  owner_generate(plan)
}
