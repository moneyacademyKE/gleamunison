//// MCP (Model Context Protocol) server protocol layer: pure JSON-RPC 2.0.
////
//// No sockets here: requests come in as strings, responses go out as strings.
//// Tool handlers are injected, so the protocol is testable without transport.

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/string
import gleamunison/json

pub type Tool {
  Tool(
    name: String,
    description: String,
    handler: fn(Dict(String, Dynamic)) -> Result(String, String),
  )
}

pub type Server {
  Server(name: String, version: String, tools: List(Tool))
}

pub type Response {
  Respond(String)
  NoReply
}

type JsonId {
  IntId(Int)
  StrId(String)
  NoId
}

type Request {
  Request(id: JsonId, method: String, params: Dict(String, Dynamic))
}

const protocol_version = "2025-06-18"

/// Handle one raw JSON-RPC request body. Pure: JSON in, JSON out.
pub fn handle_message(server: Server, body: String) -> Response {
  case json.decode(bit_array.from_string(body)) {
    Error(_) -> Respond(error_body(NoId, -32_700, "Parse error"))
    Ok(dyn) ->
      case decode.run(dyn, request_decoder()) {
        Error(_) -> Respond(error_body(NoId, -32_600, "Invalid Request"))
        Ok(req) -> dispatch(server, req)
      }
  }
}

fn request_decoder() -> decode.Decoder(Request) {
  use method <- decode.field("method", decode.string)
  use id <- decode.optional_field("id", NoId, id_decoder())
  use params <- decode.optional_field(
    "params",
    dict.new(),
    decode.dict(decode.string, decode.dynamic),
  )
  decode.success(Request(id: id, method: method, params: params))
}

fn id_decoder() -> decode.Decoder(JsonId) {
  decode.one_of(decode.map(decode.int, IntId), or: [
    decode.map(decode.string, StrId),
    decode.success(NoId),
  ])
}

fn dispatch(server: Server, req: Request) -> Response {
  case req.id {
    NoId -> NoReply
    _ ->
      case req.method {
        "initialize" -> Respond(ok_body(req.id, initialize_result(server)))
        "tools/list" -> Respond(ok_body(req.id, tools_list_result(server)))
        "tools/call" -> Respond(tools_call(server, req))
        "ping" -> Respond(ok_body(req.id, "{}"))
        _ -> Respond(error_body(req.id, -32_601, "Method not found"))
      }
  }
}

fn initialize_result(server: Server) -> String {
  "{\"protocolVersion\":"
  <> jstr(protocol_version)
  <> ",\"capabilities\":{\"tools\":{}},\"serverInfo\":{\"name\":"
  <> jstr(server.name)
  <> ",\"version\":"
  <> jstr(server.version)
  <> "}}"
}

fn tools_list_result(server: Server) -> String {
  let tools =
    list.map(server.tools, fn(t) {
      "{\"name\":"
      <> jstr(t.name)
      <> ",\"description\":"
      <> jstr(t.description)
      <> ",\"inputSchema\":{\"type\":\"object\"}}"
    })
  "{\"tools\":[" <> string.join(tools, ",") <> "]}"
}

fn tools_call(server: Server, req: Request) -> String {
  let name = case dict.get(req.params, "name") {
    Ok(dyn) ->
      case decode.run(dyn, decode.string) {
        Ok(n) -> n
        Error(_) -> ""
      }
    Error(_) -> ""
  }
  let args = case dict.get(req.params, "arguments") {
    Ok(dyn) ->
      case decode.run(dyn, decode.dict(decode.string, decode.dynamic)) {
        Ok(d) -> d
        Error(_) -> dict.new()
      }
    Error(_) -> dict.new()
  }
  case list.find(server.tools, fn(t) { t.name == name }) {
    Error(_) -> ok_body(req.id, tool_result("unknown tool: " <> name, True))
    Ok(tool) ->
      case tool.handler(args) {
        Ok(text) -> ok_body(req.id, tool_result(text, False))
        Error(err) -> ok_body(req.id, tool_result(err, True))
      }
  }
}

fn tool_result(text: String, is_error: Bool) -> String {
  let err = case is_error {
    True -> "true"
    False -> "false"
  }
  "{\"content\":[{\"type\":\"text\",\"text\":"
  <> jstr(text)
  <> "}],\"isError\":"
  <> err
  <> "}"
}

fn ok_body(id: JsonId, result: String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":"
  <> id_json(id)
  <> ",\"result\":"
  <> result
  <> "}"
}

fn error_body(id: JsonId, code: Int, message: String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":"
  <> id_json(id)
  <> ",\"error\":{\"code\":"
  <> int.to_string(code)
  <> ",\"message\":"
  <> jstr(message)
  <> "}}"
}

fn id_json(id: JsonId) -> String {
  case id {
    IntId(n) -> int.to_string(n)
    StrId(s) -> jstr(s)
    NoId -> "null"
  }
}

fn jstr(s: String) -> String {
  "\"" <> escape(s) <> "\""
}

fn escape(s: String) -> String {
  s
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
  |> string.replace("\t", "\\t")
}
