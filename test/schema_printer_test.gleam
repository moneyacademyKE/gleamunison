import gleam/option.{None, Some}
import gleam/string
import gleamunison/ast
import gleamunison/identity.{Ref, hash_bytes}
import gleamunison/schema_printer

pub fn builtin_types_print_compact_test() {
  let assert True = schema_printer.to_schema(ast.Builtin(ast.IntType)) == "int"
  let assert True =
    schema_printer.to_schema(ast.Builtin(ast.FloatType)) == "float"
  let assert True =
    schema_printer.to_schema(ast.Builtin(ast.TextType)) == "string"
  let assert True =
    schema_printer.to_schema(ast.Builtin(ast.BoolType)) == "bool"
}

pub fn function_type_prints_arrow_test() {
  let t =
    ast.Fn(
      params: [ast.Builtin(ast.IntType), ast.Builtin(ast.TextType)],
      result: ast.Builtin(ast.BoolType),
      requires: ast.Required([]),
    )
  let assert True = schema_printer.to_schema(t) == "(int, string) -> bool"
}

pub fn type_var_prints_stable_name_test() {
  let assert True = schema_printer.to_schema(ast.TypeVar(0)) == "t0"
  let assert True = schema_printer.to_schema(ast.TypeVar(3)) == "t3"
}

pub fn named_app_uses_resolver_test() {
  let list_ref = Ref(hash_bytes(<<"list-ctor">>))
  let resolver = fn(r) {
    case r == list_ref {
      True -> Some("List")
      False -> None
    }
  }
  let t = ast.App(list_ref, [ast.Builtin(ast.TextType)])
  let assert True = schema_printer.to_schema_with(t, resolver) == "List<string>"
}

pub fn unresolved_app_falls_back_to_hash_prefix_test() {
  let ref = Ref(hash_bytes(<<"mystery-ctor">>))
  let t = ast.App(ref, [ast.Builtin(ast.IntType)])
  let printed = schema_printer.to_schema(t)
  let assert True = string.starts_with(printed, "type@")
  let assert True = string.ends_with(printed, "<int>")
}

pub fn nested_generics_print_test() {
  let list_ref = Ref(hash_bytes(<<"list-ctor">>))
  let resolver = fn(r) {
    case r == list_ref {
      True -> Some("List")
      False -> None
    }
  }
  let t = ast.App(list_ref, [ast.App(list_ref, [ast.Builtin(ast.IntType)])])
  let assert True =
    schema_printer.to_schema_with(t, resolver) == "List<List<int>>"
}

pub fn zero_arg_app_prints_bare_name_test() {
  let ref = Ref(hash_bytes(<<"unit-ctor">>))
  let resolver = fn(_) { Some("Unit") }
  let assert True =
    schema_printer.to_schema_with(ast.App(ref, []), resolver) == "Unit"
}
