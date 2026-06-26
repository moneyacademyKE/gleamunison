import gleam/dict.{type Dict}
import gleamunison/identity.{type DefinitionRef, type LocalVar, Local}
import gleamunison/elab_types.{type ElaborateError, NameNotFound}

pub type ElabCtx {
  ElabCtx(
    names: Dict(String, DefinitionRef),
    bindings: Dict(String, LocalVar),
    next_local: Int,
    abilities: Dict(String, DefinitionRef),
    ops: Dict(#(String, String), Int),
  )
}

pub fn empty_elab_ctx() -> ElabCtx {
  ElabCtx(dict.new(), dict.new(), 0, dict.new(), dict.new())
}

pub fn add_binding(ctx: ElabCtx, name: String) -> #(ElabCtx, LocalVar) {
  let v = Local(ctx.next_local)
  let new_bindings = dict.insert(ctx.bindings, name, v)
  #(ElabCtx(ctx.names, new_bindings, ctx.next_local + 1, ctx.abilities, ctx.ops), v)
}

pub fn lookup_binding(ctx: ElabCtx, name: String) -> Result(LocalVar, ElaborateError) {
  case dict.get(ctx.bindings, name) {
    Ok(v) -> Ok(v)
    Error(_) -> Error(NameNotFound(name))
  }
}
