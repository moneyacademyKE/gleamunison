//// The Db effect is the only application-data mutation surface. Its host
//// owner persists an EAV transaction log separately from definition CAS.

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/string
import gleamunison/effects.{type OpHandler, ability_key}
import gleamunison/identity.{type DefinitionRef}

fn ability_ref() -> DefinitionRef {
  identity.name_ref("Db")
}

pub fn key() -> String {
  ability_key(ability_ref())
}

@external(erlang, "gleamunison_app_db", "transact")
fn transact(
  assertions: Dynamic,
  retractions: Dynamic,
) -> Result(Dynamic, String)

@external(erlang, "gleamunison_app_db", "get")
fn get(entity: Dynamic, attribute: Dynamic) -> Result(Dynamic, String)

@external(erlang, "gleamunison_app_db", "find")
fn find(attribute: Dynamic, value: Dynamic) -> Result(Dynamic, String)

@external(erlang, "gleamunison_app_db", "raise")
fn raise(reason: String) -> Dynamic

pub fn operations() -> Dict(Int, OpHandler) {
  dict.from_list([
    #(0, binary_operation("transact", transact)),
    #(1, binary_operation("get", get)),
    #(2, binary_operation("find", find)),
  ])
}

fn binary_operation(
  name: String,
  operation: fn(Dynamic, Dynamic) -> Result(Dynamic, String),
) -> OpHandler {
  fn(args, continue) {
    case args {
      [first, second] ->
        case operation(first, second) {
          Ok(value) -> continue(value)
          Error(reason) -> raise(name <> ": " <> reason)
        }
      _ ->
        raise(name <> ": expected two arguments, got " <> string.inspect(args))
    }
  }
}
