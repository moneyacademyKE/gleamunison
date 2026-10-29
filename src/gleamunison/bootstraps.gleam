import gleam/list
import gleamunison/ast
import gleamunison/bootstrap_terms
import gleamunison/identity.{type DefinitionRef}

pub type BootstrapType {
  BTInt
  BTFloat
  BTText
  BTList
  BTVar(String)
}

pub type BootstrapOp {
  BOp(name: String, inputs: List(BootstrapType), output: BootstrapType)
}

pub type BootstrapDef {
  BAbility(name: String, ops: List(BootstrapOp))
  BTerm(name: String, ref: DefinitionRef, typ: ast.Type)
}

pub fn get_init_defs_data() -> List(BootstrapDef) {
  let abilities = [
    BAbility("Console", [BOp("print", [BTText], BTInt)]),
    BAbility("Test", [BOp("expect", [BTInt], BTInt)]),
    BAbility("State", [
      BOp("get", [BTText], BTText),
      BOp("set", [BTText, BTText], BTText),
    ]),
    BAbility("Db", [
      BOp("transact", [BTList, BTList], BTInt),
      BOp("get", [BTText, BTText], BTList),
      BOp("find", [BTText, BTText], BTList),
    ]),
    BAbility("Math", [
      BOp("add", [BTInt, BTInt], BTInt),
      BOp("sub", [BTInt, BTInt], BTInt),
      BOp("mul", [BTInt, BTInt], BTInt),
    ]),
    BAbility("Show", [BOp("show", [BTVar("a")], BTText)]),
    BAbility("Remote", [
      BOp("forkAt", [BTVar("location"), BTVar("a")], BTVar("task")),
      BOp("await", [BTVar("task")], BTVar("a")),
      BOp("here", [], BTVar("location")),
    ]),
    BAbility("LLM", [
      BOp("complete", [BTText], BTText),
      BOp("complete_with_system", [BTText, BTText], BTText),
    ]),
    BAbility("Host", [BOp("ambient", [BTVar("a")], BTVar("a"))]),
    BAbility("File", [BOp("read", [BTText], BTText)]),
    BAbility("Http", [BOp("get", [BTText], BTText)]),
  ]
  list.append(
    abilities,
    list.map(bootstrap_terms.entries(), fn(entry) {
      BTerm(entry.0, entry.1, entry.2)
    }),
  )
}

/// The name of the builtin a synthetic ref belongs to, if any.
pub fn builtin_name_for(ref: DefinitionRef) -> Result(String, Nil) {
  case
    list.find_map(get_init_defs_data(), fn(definition) {
      case definition {
        BTerm(name, known, _) if known == ref -> Ok(name)
        _ -> Error(Nil)
      }
    })
  {
    Ok(name) -> Ok(name)
    Error(_) -> Error(Nil)
  }
}
