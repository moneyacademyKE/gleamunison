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

pub type HandlerError {
  MissingOperation(ability: DefinitionRef, op_name: String, op_index: Int)
  ExtraOperation(ability: DefinitionRef, op_index: Int)
  ArityMismatch(
    ability: DefinitionRef,
    op_name: String,
    op_index: Int,
    expected: Int,
    got: Int,
  )
}

pub fn validate_handler(
  cache: TypeCache,
  ability_ref: DefinitionRef,
  handler_ops: Dict(Int, #(String, Int)),
) -> Result(Nil, HandlerError) {
  case dict.get(cache.entries, ability_ref) {
    Ok(CTAbility(ops)) -> {
      let check_missing_and_arity =
        list.index_fold(ops, Ok(Nil), fn(acc, op, idx) {
          case acc {
            Error(e) -> Error(e)
            Ok(Nil) -> {
              let op_name = option.unwrap(op.name, "?")
              case dict.get(handler_ops, idx) {
                Error(_) -> Error(MissingOperation(ability_ref, op_name, idx))
                Ok(#(_, arity)) -> {
                  let expected = list.length(op.inputs)
                  case arity == expected {
                    True -> Ok(Nil)
                    False ->
                      Error(ArityMismatch(
                        ability_ref,
                        op_name,
                        idx,
                        expected,
                        arity,
                      ))
                  }
                }
              }
            }
          }
        })
      case check_missing_and_arity {
        Error(e) -> Error(e)
        Ok(Nil) -> {
          // Check for extra operations in handler_ops
          let max_idx = list.length(ops)
          let keys = dict.keys(handler_ops)
          case list.find(keys, fn(k) { k < 0 || k >= max_idx }) {
            Ok(extra_idx) -> Error(ExtraOperation(ability_ref, extra_idx))
            Error(_) -> Ok(Nil)
          }
        }
      }
    }
    _ -> Ok(Nil)
  }
}
