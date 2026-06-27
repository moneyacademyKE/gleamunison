import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option}
import gleamunison/ast
import gleamunison/identity.{type DefinitionRef}

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
  TypeMismatch(expected: ast.Type, actual: ast.Type, message: String)
  InfiniteType(variable: Int, typ: ast.Type)
  UnhandledAbility(ast.AbilityRef)
  ImpureContext(ast.Requirement)
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
