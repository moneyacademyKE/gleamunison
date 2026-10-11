import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/string
import gleamunison/mcp.{type Tool, NoReply, Respond, Tool}

fn stub_tools() -> List(Tool) {
  [
    Tool(
      name: "echo",
      description: "echoes the text argument",
      handler: fn(args: dict.Dict(String, Dynamic)) {
        case dict.get(args, "text") {
          Ok(dyn) -> {
            let assert Ok(text) = decode.run(dyn, decode.string)
            Ok("echo: " <> text)
          }
          Error(_) -> Error("missing text argument")
        }
      },
    ),
    Tool(name: "fail", description: "always fails", handler: fn(_) {
      Error("boom")
    }),
  ]
}

fn server() -> mcp.Server {
  mcp.Server(name: "gleamunison-test", version: "0.0.1", tools: stub_tools())
}

pub fn initialize_test() {
  let req =
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}"
  let assert Respond(body) = mcp.handle_message(server(), req)
  let assert True = string.contains(body, "\"id\":1")
  let assert True = string.contains(body, "gleamunison-test")
  let assert True = string.contains(body, "protocolVersion")
}

pub fn initialized_notification_no_reply_test() {
  let req = "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}"
  let assert NoReply = mcp.handle_message(server(), req)
}

pub fn tools_list_test() {
  let req = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}"
  let assert Respond(body) = mcp.handle_message(server(), req)
  let assert True = string.contains(body, "\"name\":\"echo\"")
  let assert True = string.contains(body, "\"name\":\"fail\"")
  let assert True = string.contains(body, "inputSchema")
}

pub fn tools_call_ok_test() {
  let req =
    "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"echo\",\"arguments\":{\"text\":\"hi\"}}}"
  let assert Respond(body) = mcp.handle_message(server(), req)
  let assert True = string.contains(body, "echo: hi")
  let assert True = string.contains(body, "\"isError\":false")
}

pub fn tools_call_handler_error_test() {
  let req =
    "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"fail\",\"arguments\":{}}}"
  let assert Respond(body) = mcp.handle_message(server(), req)
  let assert True = string.contains(body, "boom")
  let assert True = string.contains(body, "\"isError\":true")
}

pub fn tools_call_unknown_tool_test() {
  let req =
    "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"nope\",\"arguments\":{}}}"
  let assert Respond(body) = mcp.handle_message(server(), req)
  let assert True = string.contains(body, "\"isError\":true")
  let assert True = string.contains(body, "nope")
}

pub fn unknown_method_test() {
  let req = "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"frobnicate\"}"
  let assert Respond(body) = mcp.handle_message(server(), req)
  let assert True = string.contains(body, "-32601")
  let assert True = string.contains(body, "\"id\":6")
}

pub fn invalid_json_test() {
  let assert Respond(body) = mcp.handle_message(server(), "{not json")
  let assert True = string.contains(body, "-32700")
  let assert True = string.contains(body, "\"id\":null")
}
