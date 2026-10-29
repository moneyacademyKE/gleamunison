//// Strict, provider-independent MCP input for bounded generation.
//// Storage, branch, credentials, and provider selection never enter as data.

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleamunison/ast
import gleamunison/generation_loop

const allowed_fields = [
  "template", "variables", "signature", "max_attempts", "target",
]

pub fn plan(
  args: Dict(String, Dynamic),
) -> Result(generation_loop.Plan, String) {
  use Nil <- result.try(
    case dict.keys(args) |> list.all(list.contains(allowed_fields, _)) {
      True -> Ok(Nil)
      False ->
        Error(
          "agent_generate: unknown argument; expected template, variables, signature, max_attempts, target",
        )
    },
  )
  use template <- result.try(required_string(args, "template"))
  use signature <- result.try(required_string(args, "signature"))
  use typ <- result.try(signature_type(signature))
  use variables <- result.try(optional_variables(args))
  use attempts <- result.try(optional_attempts(args))
  use target <- result.try(optional_target(args))
  Ok(generation_loop.Plan(
    template: instructions(template, target),
    variables:,
    signature: typ,
    max_attempts: attempts,
    target:,
  ))
}

fn instructions(template: String, target: Option(String)) -> String {
  let bundle = case target {
    None ->
      "Source must define one target term and its passing test_<name>. "
      <> "Use no unadmitted helpers. "
    Some(name) ->
      "Source must define the target term named "
      <> name
      <> ", any helper terms, and passing test_<name> definitions. "
  }
  template
  <> "\n\nReturn only a JSON object with exactly source and signature. "
  <> bundle
  <> "Repeat this requested signature exactly: {{signature}}."
}

fn optional_target(
  args: Dict(String, Dynamic),
) -> Result(Option(String), String) {
  case dict.get(args, "target") {
    Error(Nil) -> Ok(None)
    Ok(_) -> required_string(args, "target") |> result.map(Some)
  }
}

fn required_string(
  args: Dict(String, Dynamic),
  field: String,
) -> Result(String, String) {
  use value <- result.try(
    dict.get(args, field)
    |> result.replace_error(
      "agent_generate: missing string argument: " <> field,
    ),
  )
  use text <- result.try(
    decode.run(value, decode.string)
    |> result.replace_error(
      "agent_generate: expected string argument: " <> field,
    ),
  )
  case string.trim(text) {
    "" -> Error("agent_generate: empty argument: " <> field)
    _ -> Ok(text)
  }
}

fn optional_variables(
  args: Dict(String, Dynamic),
) -> Result(List(#(String, String)), String) {
  case dict.get(args, "variables") {
    Error(Nil) -> Ok([])
    Ok(value) ->
      case decode.run(value, decode.dict(decode.string, decode.dynamic)) {
        Error(_) -> Error("agent_generate: variables must be a string map")
        Ok(values) ->
          list.try_map(dict.to_list(values), fn(pair) {
            let #(key, dynamic_value) = pair
            decode.run(dynamic_value, decode.string)
            |> result.map(fn(text) { #(key, text) })
            |> result.replace_error(
              "agent_generate: variables must be a string map",
            )
          })
      }
  }
}

fn optional_attempts(args: Dict(String, Dynamic)) -> Result(Int, String) {
  case dict.get(args, "max_attempts") {
    Error(Nil) -> Ok(3)
    Ok(value) ->
      decode.run(value, decode.int)
      |> result.replace_error("agent_generate: max_attempts must be an integer")
  }
}

/// The deliberately small external schema vocabulary. Internal callers can
/// still construct the full ast.Type directly; no speculative parser here.
fn signature_type(text: String) -> Result(ast.Type, String) {
  case string.split_once(text, " -> ") {
    Error(Nil) -> scalar(string.trim(text))
    Ok(#(parameters, result_text)) -> {
      use inputs <- result.try(parameter_types(parameters))
      use output <- result.try(signature_type(result_text))
      case list.length(inputs) <= 8 {
        True -> Ok(ast.Fn(inputs, output, ast.Required([])))
        False ->
          Error("agent_generate: function signature exceeds 8 parameters")
      }
    }
  }
}

fn parameter_types(text: String) -> Result(List(ast.Type), String) {
  let trimmed = string.trim(text)
  case string.starts_with(trimmed, "(") && string.ends_with(trimmed, ")") {
    False -> Error("agent_generate: function parameters must be parenthesized")
    True -> {
      let inner = string.slice(trimmed, 1, string.length(trimmed) - 2)
      case string.trim(inner) {
        "" -> Ok([])
        _ ->
          string.split(inner, ",")
          |> list.map(string.trim)
          |> list.try_map(scalar)
      }
    }
  }
}

fn scalar(text: String) -> Result(ast.Type, String) {
  case text {
    "int" -> Ok(ast.Builtin(ast.IntType))
    "float" -> Ok(ast.Builtin(ast.FloatType))
    "string" -> Ok(ast.Builtin(ast.TextType))
    "bool" -> Ok(ast.Builtin(ast.BoolType))
    "list" -> Ok(ast.Builtin(ast.ListType))
    _ ->
      Error(
        "agent_generate: signature must use int, float, string, bool, list, "
        <> "or (parameters) -> result; received "
        <> text,
      )
  }
}
