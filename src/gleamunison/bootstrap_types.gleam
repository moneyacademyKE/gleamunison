//// Type constructors supplied by the runtime rather than user declarations.
//// They are references in ordinary Type.App values, not a second type model.

import gleam/bit_array
import gleam/list
import gleam/option.{type Option, None, Some}
import gleamunison/ast
import gleamunison/identity.{type DefinitionRef, Ref, hash_bytes}

pub fn named(name: String) -> DefinitionRef {
  Ref(hash_bytes(bit_array.from_string(name)))
}

pub fn apply(name: String, args: List(ast.Type)) -> ast.Type {
  ast.App(named(name), args)
}

pub fn list_of(element: ast.Type) -> ast.Type {
  apply("List", [element])
}

pub fn dict_of(key: ast.Type, value: ast.Type) -> ast.Type {
  apply("Dict", [key, value])
}

pub fn set_of(element: ast.Type) -> ast.Type {
  apply("Set", [element])
}

pub fn pair_of(first: ast.Type, second: ast.Type) -> ast.Type {
  apply("Pair", [first, second])
}

pub fn either_of(left: ast.Type, right: ast.Type) -> ast.Type {
  apply("Either", [left, right])
}

pub fn process() -> ast.Type {
  apply("Process", [])
}

/// A host value whose runtime representation carries no language type tag.
/// This is explicit and local to the FFI boundary, unlike TypeVar(-1), which
/// means inference failed and must never become a stored identity.
pub fn host_value() -> ast.Type {
  apply("HostValue", [])
}

/// The single owner of the builtin type-name list: resolves a runtime
/// type-constructor ref to its printed name, or None for user types.
pub fn type_name(ref: DefinitionRef) -> Option(String) {
  case
    list.find(
      ["List", "Dict", "Set", "Pair", "Either", "Process", "HostValue"],
      fn(name) { named(name) == ref },
    )
  {
    Ok(name) -> Some(name)
    Error(_) -> None
  }
}

pub fn is_type_ref(ref: DefinitionRef) -> Bool {
  case type_name(ref) {
    Some(_) -> True
    _ -> False
  }
}
