import gleam/dict
import gleam/option.{Some}
import gleamunison/identity.{Ref, hash_bytes}
import gleamunison/types.{
  CTAbility, OperationType, TypeCache, validate_handler, MissingOperation, ArityMismatch, ExtraOperation
}
import gleamunison/ast

pub fn handler_missing_op_test() {
  let ability_ref = Ref(hash_bytes(<<"myability">>))
  let op = OperationType(
    name: Some("read"),
    inputs: [ast.Builtin(ast.IntType)],
    output: ast.Builtin(ast.TextType)
  )
  let cache = TypeCache(entries: dict.from_list([#(ability_ref, CTAbility([op]))]))
  
  let assert Error(MissingOperation(ref, "read", 0)) = validate_handler(cache, ability_ref, dict.new())
  let assert True = ref == ability_ref
}

pub fn handler_arity_mismatch_test() {
  let ability_ref = Ref(hash_bytes(<<"myability">>))
  let op = OperationType(
    name: Some("read"),
    inputs: [ast.Builtin(ast.IntType)],
    output: ast.Builtin(ast.TextType)
  )
  let cache = TypeCache(entries: dict.from_list([#(ability_ref, CTAbility([op]))]))
  
  let handler_ops = dict.from_list([#(0, #("read", 2))])
  let assert Error(ArityMismatch(ref, "read", 0, expected: 1, got: 2)) =
    validate_handler(cache, ability_ref, handler_ops)
  let assert True = ref == ability_ref
}

pub fn handler_extra_op_test() {
  let ability_ref = Ref(hash_bytes(<<"myability">>))
  let op = OperationType(
    name: Some("read"),
    inputs: [ast.Builtin(ast.IntType)],
    output: ast.Builtin(ast.TextType)
  )
  let cache = TypeCache(entries: dict.from_list([#(ability_ref, CTAbility([op]))]))
  
  let handler_ops = dict.from_list([#(0, #("read", 1)), #(5, #("extra", 0))])
  let assert Error(ExtraOperation(ref, 5)) = validate_handler(cache, ability_ref, handler_ops)
  let assert True = ref == ability_ref
}

pub fn handler_valid_test() {
  let ability_ref = Ref(hash_bytes(<<"myability">>))
  let op = OperationType(
    name: Some("read"),
    inputs: [ast.Builtin(ast.IntType)],
    output: ast.Builtin(ast.TextType)
  )
  let cache = TypeCache(entries: dict.from_list([#(ability_ref, CTAbility([op]))]))
  
  let handler_ops = dict.from_list([#(0, #("read", 1))])
  let assert Ok(Nil) = validate_handler(cache, ability_ref, handler_ops)
}
