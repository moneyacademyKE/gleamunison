import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/list
import gleamunison/identity.{type DefinitionRef, runtime_module_name}

pub type HandlerFrame {
  HandlerFrame(ability: DefinitionRef, ops: Dict(Int, OpHandler))
}

pub type OpHandler =
  fn(List(Dynamic), fn(Dynamic) -> Dynamic) -> Dynamic

pub type RuntimeConfig {
  RuntimeConfig(ambient_handlers: List(HandlerFrame))
}

@external(erlang, "gleamunison_effets", "handle_comp")
fn ffi_handle_comp(handler: Dynamic, thunk: fn() -> Dynamic) -> Dynamic

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn to_dynamic(val: any) -> Dynamic

/// The handler-stack key for an ability: "m_" + last 8 of its hash.
/// Public so tooling (transcripts, capability gates) keys frames the same
/// way the runtime does.
pub fn ability_key(ref: DefinitionRef) -> String {
  runtime_module_name(ref)
}

pub fn run(cfg: RuntimeConfig, entry: fn() -> Dynamic) -> Dynamic {
  list.fold_right(cfg.ambient_handlers, entry, fn(thunk, frame) {
    let key = ability_key(frame.ability)
    fn() { ffi_handle_comp(to_dynamic(#(key, frame.ops)), thunk) }
  })()
}
