//// Type -> compact prompt schema printer (gap analysis concept D).
////
//// BAML-style compact notation over the core Type language — data only:
//// ability requirements are elided (a schema describes the shape of a value,
//// not the effects that produced it). Named constructors resolve through a
//// caller-supplied resolver; unresolved refs print as type@<hash8>, which is
//// still a stable, content-addressed token an agent can look up.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleamunison/ast
import gleamunison/identity.{type DefinitionRef, Ref, hash_to_debug_string}

pub type NameResolver =
  fn(DefinitionRef) -> Option(String)

/// Print with no name resolution (hash fallbacks for applied constructors).
pub fn to_schema(t: ast.Type) -> String {
  to_schema_with(t, fn(_) { None })
}

pub fn to_schema_with(t: ast.Type, resolver: NameResolver) -> String {
  case t {
    ast.Builtin(b) -> builtin_name(b)
    ast.TypeVar(i) -> "t" <> int.to_string(i)
    ast.AbilityVar(i) -> "e" <> int.to_string(i)
    ast.Fn(params: params, result: result, requires: _) ->
      "("
      <> join_types(params, resolver)
      <> ") -> "
      <> to_schema_with(result, resolver)
    ast.App(name: ref, args: args) -> app_name(ref, args, resolver)
  }
}

fn builtin_name(b: ast.BuiltinType) -> String {
  case b {
    ast.IntType -> "int"
    ast.FloatType -> "float"
    ast.TextType -> "string"
    ast.BoolType -> "bool"
    ast.ListType -> "list"
    ast.HandlerType -> "handler"
  }
}

fn join_types(types: List(ast.Type), resolver: NameResolver) -> String {
  types
  |> list.map(to_schema_with(_, resolver))
  |> string.join(", ")
}

fn app_name(
  ref: DefinitionRef,
  args: List(ast.Type),
  resolver: NameResolver,
) -> String {
  let name = case resolver(ref) {
    Some(n) -> n
    None -> {
      let Ref(h) = ref
      let hex = hash_to_debug_string(h)
      "type@" <> string.slice(hex, 0, 8)
    }
  }
  case args {
    [] -> name
    _ -> name <> "<" <> join_types(args, resolver) <> ">"
  }
}
