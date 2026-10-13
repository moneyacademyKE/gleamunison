//// Shared LSP types and response builders. Both the protocol core
//// (lsp.gleam) and the language features (lsp_features.gleam) need them;
//// keeping them here breaks the import cycle between the two.

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/string

/// Server state: the open documents. Stateless services can't answer
/// "what is THIS symbol in THIS file" — hover/definition/completion read
/// the document the client opened.
pub type State {
  State(docs: dict.Dict(String, String))
}

pub fn new_state() -> State {
  State(docs: dict.new())
}

pub fn open_doc(state: State, uri: String, text: String) -> State {
  State(docs: dict.insert(state.docs, uri, text))
}

pub type Message {
  Message(id: Option(Dynamic), method: String, params: dict.Dict(String, Dynamic))
}

pub fn respond(id: Dynamic, result: String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":"
  <> id_json(id)
  <> ",\"result\":"
  <> result
  <> "}"
}

pub fn error_response(id: Dynamic, code: Int, message: String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":"
  <> id_json(id)
  <> ",\"error\":{\"code\":"
  <> int.to_string(code)
  <> ",\"message\":"
  <> jstr(message)
  <> "}}"
}

pub fn id_json(id: Dynamic) -> String {
  case decode.run(id, decode.int) {
    Ok(n) -> int.to_string(n)
    Error(_) ->
      case decode.run(id, decode.string) {
        Ok(s) -> jstr(s)
        Error(_) -> "null"
      }
  }
}

pub fn jstr(s: String) -> String {
  let escaped =
    s
    |> string.replace("\\", "\\\\")
    |> string.replace("\"", "\\\"")
    |> string.replace("\n", "\\n")
    |> string.replace("\r", "\\r")
    |> string.replace("\t", "\\t")
  "\"" <> escaped <> "\""
}
