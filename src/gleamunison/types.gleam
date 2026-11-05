import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleamunison/ast
import gleamunison/identity.{type DefinitionRef, ref_hex}
import gleamunison/type_pretty

pub type ComputedType {
  CTTerm(typ: ast.Type)
  CTType
  CTAbility(operations: List(OperationType))
}

pub type OperationType {
  OperationType(name: Option(String), inputs: List(ast.Type), output: ast.Type)
}

pub type TypeCache {
  TypeCache(entries: Dict(DefinitionRef, ComputedType))
}

pub fn empty_cache() -> TypeCache {
  TypeCache(entries: dict.new())
}

pub type InferenceError {
  UnboundVariable(Int)
  TypeMismatch(
    expected: ast.Type,
    actual: ast.Type,
    message: String,
    /// The elaborated subterm that failed, when the failing site had one in
    /// scope. When that term is a `ast.Located`, its span is the source
    /// location of the error — elab_def lifts it into an `At` wrapper.
    term: Option(ast.Term),
  )
  InfiniteType(variable: Int, typ: ast.Type)
  UnhandledAbility(ast.AbilityRef)
  ImpureContext(ast.Requirement)
  LinearityViolation(term: String, expected: String)
}

/// Render one element of a requirement as a sentence. A ReqVar is an
/// anonymous ability variable, so it is named by position, not dumped.
fn describe_req_element(element: ast.ReqElement) -> String {
  case element {
    ast.Concrete(ast.AbilityRef(decl)) -> ref_hex(decl)
    ast.ReqVar(index) -> "ability variable " <> int.to_string(index)
  }
}

/// Render an inference error for the user. Types go through the
/// pretty-printer (the repo's one type renderer); ability references go
/// through ref_hex; the remaining variants keep their payloads in words.
/// No embedded subterm is rendered — spans are attached by the caller.
pub fn describe_inference_error(error: InferenceError) -> String {
  case error {
    UnboundVariable(index) -> "unbound variable " <> int.to_string(index)
    TypeMismatch(expected, actual, message, _) ->
      message
      <> ": expected "
      <> type_pretty.pretty_print(expected)
      <> ", got "
      <> type_pretty.pretty_print(actual)
    InfiniteType(variable, typ) ->
      "infinite type: "
      <> type_pretty.pretty_print(typ)
      <> " refers to variable "
      <> int.to_string(variable)
    UnhandledAbility(ast.AbilityRef(decl)) ->
      "unhandled ability " <> ref_hex(decl)
    ImpureContext(ast.Required(abilities)) ->
      "impure context: required abilities "
      <> list.map(abilities, describe_req_element)
      |> list_fold_join()
    LinearityViolation(term, expected) -> term <> " must be used " <> expected
  }
}

fn list_fold_join(items: List(String)) -> String {
  case items {
    [] -> "none"
    [first, ..rest] ->
      list.fold(rest, first, fn(acc, item) { acc <> ", " <> item })
  }
}
