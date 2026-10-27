//// Fixed graph queries over the selected session's definition datoms.
//// General Datalog programs remain user-space code; MCP does not evaluate them.

import gleam/list
import gleamunison/agent_read_model
import gleamunison/codebase_index.{type Datom}

/// Names of definitions that reference `name`, in established index order.
pub fn callers_of(
  entries: List(agent_read_model.Entry),
  name: String,
) -> List(String) {
  let datoms = codebase_index.datoms_of_entries(entries)
  entities_with(datoms, "def/dep", name)
  |> list.flat_map(values_for_entity(datoms, _, "def/name"))
}

/// In-corpus names referenced by `name`, preserving dependency order.
pub fn deps_of(
  entries: List(agent_read_model.Entry),
  name: String,
) -> List(String) {
  let datoms = codebase_index.datoms_of_entries(entries)
  entities_with(datoms, "def/name", name)
  |> list.flat_map(values_for_entity(datoms, _, "def/dep"))
}

/// Names of definitions whose kind equals `kind`, in established index order.
pub fn defs_by_kind(
  entries: List(agent_read_model.Entry),
  kind: String,
) -> List(String) {
  let datoms = codebase_index.datoms_of_entries(entries)
  entities_with(datoms, "def/kind", kind)
  |> list.flat_map(values_for_entity(datoms, _, "def/name"))
}

fn entities_with(
  datoms: List(Datom),
  attr: String,
  value: String,
) -> List(Int) {
  list.filter_map(datoms, fn(datom) {
    case datom.attr == attr && datom.value == value {
      True -> Ok(datom.entity)
      False -> Error(Nil)
    }
  })
  |> list.unique
}

fn values_for_entity(
  datoms: List(Datom),
  entity: Int,
  attr: String,
) -> List(String) {
  list.filter_map(datoms, fn(datom) {
    case datom.entity == entity && datom.attr == attr {
      True -> Ok(datom.value)
      False -> Error(Nil)
    }
  })
}
