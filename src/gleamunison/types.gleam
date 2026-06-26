import gleam/dict.{type Dict}
import gleam/option.{type Option}
import gleamunison/identity.{type DefinitionRef}
import gleamunison/ast as ast

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
  ArityMismatch(ability: DefinitionRef, op_name: String, op_index: Int, expected: Int, got: Int)
}

pub fn validate_handler(
  _cache: TypeCache,
  _ability_ref: DefinitionRef,
  _handler_ops: Dict(Int, #(String, Int)),
) -> Result(Nil, HandlerError) {
  Ok(Nil)
}
