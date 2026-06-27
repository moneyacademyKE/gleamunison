import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/string
import gleamunison/identity.{type DefinitionRef, Ref, hash_to_debug_string}

pub type HandlerFrame { HandlerFrame(ability: DefinitionRef, ops: Dict(Int, OpHandler)) }
pub type OpHandler = fn(List(Dynamic), fn(Dynamic) -> Dynamic) -> Dynamic
pub type RuntimeConfig { RuntimeConfig(ambient_handlers: List(HandlerFrame)) }

@external(erlang, "gleamunison_effets", "handle_comp")
fn ffi_handle_comp(handler: Dynamic, thunk: fn() -> Dynamic) -> Dynamic

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn to_dynamic(val: any) -> Dynamic

fn ability_key(ref: DefinitionRef) -> String {
  let Ref(h) = ref
  let full = hash_to_debug_string(h)
  "m_" <> string.slice(full, string.length(full) - 8, 8)
}

pub fn run(cfg: RuntimeConfig, entry: fn() -> Dynamic) -> Dynamic {
  list.fold_right(cfg.ambient_handlers, entry, fn(thunk, frame) {
    let key = ability_key(frame.ability)
    fn() { ffi_handle_comp(to_dynamic(#(key, frame.ops)), thunk) }
  })()
}
