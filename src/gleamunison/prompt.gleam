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
import gleam/string
import gleamunison/codebase.{type Codebase}
import gleamunison/identity.{
  type DefinitionRef, Ref, hash_bytes, hash_to_debug_string,
}

pub type PromptError {
  NotFound
  Unreadable
  MissingVar(String)
  Storage(reason: String)
}

/// Displayable hash identity for traces and pins.
pub fn ref_hex(ref: DefinitionRef) -> String {
  let Ref(h) = ref
  hash_to_debug_string(h)
}

/// Store a prompt template; returns the codebase and its content hash.
pub fn put(cb: Codebase, template: String) -> #(Codebase, DefinitionRef) {
  let bytes = bit_array.from_string(template)
  let ref =
    Ref(
      hash_bytes(
        bit_array.concat([
          bit_array.from_string("promptdef:"),
          bytes,
        ]),
      ),
    )
  #(codebase.insert_raw(cb, ref, bytes), ref)
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

pub fn render_by_hash(
  cb: Codebase,
  ref: DefinitionRef,
  vars: List(#(String, String)),
) -> Result(String, PromptError) {
  case get(cb, ref) {
    Error(e) -> Error(e)
    Ok(template) -> render(template, vars)
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
