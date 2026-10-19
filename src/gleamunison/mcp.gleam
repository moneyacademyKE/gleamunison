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
      case validate_request(dyn) {
        Error(_) -> Respond(error_body(NoId, -32_600, "Invalid Request"))
        Ok(_) ->
          case decode.run(dyn, request_decoder()) {
            Error(_) -> Respond(error_body(NoId, -32_600, "Invalid Request"))
            Ok(req) -> dispatch(server, req)
          }
      }
  }
}

fn validate_request(dyn: Dynamic) -> Result(Nil, Nil) {
  case decode.run(dyn, decode.dict(decode.string, decode.dynamic)) {
    Error(_) -> Error(Nil)
    Ok(fields) ->
      case dict.get(fields, "jsonrpc"), dict.get(fields, "method") {
        Ok(version_dyn), Ok(method_dyn) ->
          case
            decode.run(version_dyn, decode.string),
            decode.run(method_dyn, decode.string)
          {
            Ok("2.0"), Ok(_) -> Ok(Nil)
            _, _ -> Error(Nil)
          }
        _, _ -> Error(Nil)
      }
  }
}

fn request_decoder() -> decode.Decoder(Request) {
  use _jsonrpc <- decode.field("jsonrpc", decode.string)
  use method <- decode.field("method", decode.string)
  use id <- decode.optional_field("id", NoId, id_decoder())
  use params <- decode.optional_field(
    "params",
    dict.new(),
    decode.one_of(decode.dict(decode.string, decode.dynamic), or: [
      decode.success(dict.new()),
    ]),
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

pub fn tools_list_result(server: Server) -> String {
  let tools =
    list.map(server.tools, fn(t) {
      "{\"name\":"
      <> jstr(t.name)
      <> ",\"description\":"
      <> jstr(t.description)
      <> ",\"inputSchema\":"
      <> tool_schema(t.name)
      <> "}"
    })
  "{\"tools\":[" <> string.join(tools, ",") <> "]}"
}

fn tool_schema(name: String) -> String {
  case name {
    "get_definition" ->
      "{\"type\":\"object\",\"required\":[\"name\"],\"properties\":{\"name\":{\"type\":\"string\"}}}"
    "search_definitions" ->
      "{\"type\":\"object\",\"required\":[\"query\"],\"properties\":{\"query\":{\"type\":\"string\"}}}"
    "eval" ->
      "{\"type\":\"object\",\"required\":[\"expr\"],\"properties\":{\"expr\":{\"type\":\"string\"}}}"
    "callers_of" ->
      "{\"type\":\"object\",\"required\":[\"name\"],\"properties\":{\"name\":{\"type\":\"string\"}}}"
    "deps_of" ->
      "{\"type\":\"object\",\"required\":[\"name\"],\"properties\":{\"name\":{\"type\":\"string\"}}}"
    "defs_by_kind" ->
      "{\"type\":\"object\",\"required\":[\"kind\"],\"properties\":{\"kind\":{\"type\":\"string\"}}}"
    _ -> "{\"type\":\"object\",\"additionalProperties\":true}"
  }
}

fn tools_call(server: Server, req: Request) -> String {
  case dict.get(req.params, "name"), dict.get(req.params, "arguments") {
    Error(_), _ -> error_body(req.id, -32_602, "Invalid params")
    Ok(name_dyn), Error(_) -> error_body(req.id, -32_602, "Invalid params")
    Ok(name_dyn), Ok(args_dyn) ->
      case
        decode.run(name_dyn, decode.string),
        decode.run(args_dyn, decode.dict(decode.string, decode.dynamic))
      {
        Ok(name), Ok(args) -> dispatch_tool(server, req.id, name, args)
        _, _ -> error_body(req.id, -32_602, "Invalid params")
      }
  }
}

fn dispatch_tool(
  server: Server,
  id: JsonId,
  name: String,
  args: Dict(String, Dynamic),
) -> String {
  case list.find(server.tools, fn(t) { t.name == name }) {
    Error(_) -> ok_body(id, tool_result("unknown tool: " <> name, True))
    Ok(tool) ->
      case tool.handler(args) {
        Ok(text) -> ok_body(id, tool_result(text, False))
        Error(err) -> ok_body(id, tool_result(err, True))
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

pub fn json_string(s: String) -> String {
  case json.encode(s) {
    Ok(encoded) ->
      case bit_array.to_string(encoded) {
        Ok(value) -> value
        Error(_) -> "\"\""
      }
    Error(_) -> "\"\""
  }
}

fn jstr(s: String) -> String {
  json_string(s)
}
