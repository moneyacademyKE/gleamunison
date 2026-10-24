//// Lisp literals, not JSON literals: this exactly matches lexer.read_string.

import gleam/string

pub fn text(value: String) -> String {
  let escaped =
    value
    |> string.replace("\\", "\\\\")
    |> string.replace("\"", "\\\"")
    |> string.replace("\n", "\\n")
  "\"" <> escaped <> "\""
}
