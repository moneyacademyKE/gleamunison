//// Shared LSP types and response builders. Both the protocol core
//// (lsp.gleam) and the language features (lsp_features.gleam) need them;
//// keeping them here breaks the import cycle between the two.

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/option.{type Option}
import gleamunison/json

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
  Message(
    id: Option(Dynamic),
    method: String,
    params: dict.Dict(String, Dynamic),
  )
}

pub fn respond(id: Dynamic, result: String) -> String {
  json.respond(json.id_of_dynamic(id), result)
}

pub fn error_response(id: Dynamic, code: Int, message: String) -> String {
  json.error_respond(json.id_of_dynamic(id), code, message)
}
