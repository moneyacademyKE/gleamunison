//// Content-addressed prompts (gap analysis concept C).
////
//// Prompts are template strings stored as definitions in the codebase DAG:
//// the ref is the hash of the domain-tagged content, so a prompt's hash is
//// immutable identity, audit tag, and deployment handle in one. Hash-pinned
//// rollout = swap which ref your root points at; A/B = two refs; peer sync
//// = the existing pull machinery, conflict-free by construction.
////
//// Rendering is RAW {{var}} substitution — deliberately NOT the web
//// template engine, whose HTML escaping would corrupt prompt payloads.

import gleam/bit_array
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleamunison/codebase.{type Codebase}
import gleamunison/identity.{type DefinitionRef, Ref, hash_bytes}

pub type PromptError {
  NotFound
  Unreadable
  MissingVar(String)
  Storage(reason: String)
}

/// Store a prompt without hiding a failed CAS write behind a valid-looking ref.
pub fn put_checked(
  cb: Codebase,
  template: String,
) -> Result(#(Codebase, DefinitionRef), PromptError) {
  let ref = template_ref(template)
  codebase.insert_raw_checked(cb, ref, bit_array.from_string(template))
  |> result.map_error(fn(error) { Storage(string.inspect(error)) })
  |> result.map(fn(updated) { #(updated, ref) })
}

fn template_ref(template: String) -> DefinitionRef {
  let bytes = bit_array.from_string(template)
  Ref(
    hash_bytes(
      bit_array.concat([
        bit_array.from_string("promptdef:"),
        bytes,
      ]),
    ),
  )
}

/// Fetch a prompt template by hash.
pub fn get(cb: Codebase, ref: DefinitionRef) -> Result(String, PromptError) {
  let adapter = codebase.get_adapter(cb)
  case adapter.lookup(ref) {
    Ok(Some(bytes)) ->
      case bit_array.to_string(bytes) {
        Ok(s) -> Ok(s)
        Error(_) -> Error(Unreadable)
      }
    Ok(None) -> Error(NotFound)
    Error(_) -> Error(Storage("lookup failed"))
  }
}

/// The {{var}} names a template expects, deduped in first-appearance order.
pub fn vars(template: String) -> List(String) {
  extract_vars(template, [])
}

/// Raw substitution of {{vars}} — no HTML escaping (prompts are not markup).
pub fn render(
  template: String,
  vars: List(#(String, String)),
) -> Result(String, PromptError) {
  let needed = extract_vars(template, [])
  case list.find(needed, fn(n) { !has_var(vars, n) }) {
    Ok(missing) -> Error(MissingVar(missing))
    Error(_) -> Ok(substitute(template, vars))
  }
}

fn has_var(vars: List(#(String, String)), name: String) -> Bool {
  list.any(vars, fn(v) { v.0 == name })
}

fn extract_vars(t: String, acc: List(String)) -> List(String) {
  case string.split_once(t, "{{") {
    Error(_) -> acc
    Ok(#(_, rest)) ->
      case string.split_once(rest, "}}") {
        Error(_) -> acc
        Ok(#(name, after)) -> extract_vars(after, append_unique(acc, name))
      }
  }
}

fn append_unique(xs: List(String), x: String) -> List(String) {
  case list.contains(xs, x) {
    True -> xs
    False -> list.append(xs, [x])
  }
}

fn substitute(template: String, vars: List(#(String, String))) -> String {
  list.fold(vars, template, fn(t, v) {
    string.replace(t, "{{" <> v.0 <> "}}", v.1)
  })
}
