import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/string
import gleamunison/capability
import gleamunison/effects.{type OpHandler, HandlerFrame}
import gleamunison/llm
import gleeunit/should

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn to_dynamic(val: a) -> Dynamic

@external(erlang, "gleamunison_ffi", "from_dynamic")
fn unsafe_coerce(val: Dynamic) -> a

@external(erlang, "gleamunison_ffi_test", "rescue")
fn ffi_rescue(f: fn() -> Dynamic) -> Result(Dynamic, String)

fn ok_handler() -> OpHandler {
  fn(args: List(Dynamic), cont: fn(Dynamic) -> Dynamic) -> Dynamic {
    let arg0: List(String) = unsafe_coerce(to_dynamic(args))
    let head = case arg0 {
      [x, ..] -> x
      _ -> ""
    }
    cont(to_dynamic("ran:" <> head))
  }
}

fn llm_frame(handler: OpHandler) {
  HandlerFrame(ability: llm.ability_ref(), ops: dict.from_list([#(0, handler)]))
}

fn llm_key() -> String {
  capability.frame_key(llm_frame(ok_handler()))
}

pub fn allowed_ability_executes_under_policy_test() {
  let policy = capability.allow([llm_key()])
  let frames = capability.guard_frames(policy, [llm_frame(ok_handler())])
  capability.check(policy, frames) |> should.be_ok
  let assert [frame] = frames
  let assert Ok(handler) = dict.get(frame.ops, 0)
  let result = handler([to_dynamic("yes")], fn(d) { d })
  unsafe_coerce(result) |> should.equal("ran:yes")
}

pub fn denied_ability_raises_capability_denied_test() {
  let policy = capability.allow([])
  let frames = capability.guard_frames(policy, [llm_frame(ok_handler())])
  capability.check(policy, frames) |> should.be_error
  let assert [frame] = frames
  let assert Ok(handler) = dict.get(frame.ops, 0)
  let result = ffi_rescue(fn() { handler([to_dynamic("no")], fn(d) { d }) })
  let assert Error(reason) = result
  string.contains(reason, "capability_denied") |> should.be_true
}

pub fn preflight_lists_denied_abilities_test() {
  let policy = capability.allow([])
  let frames = [llm_frame(ok_handler())]
  let assert Error(denied) = capability.check(policy, frames)
  denied |> should.equal([llm_key()])
}

pub fn catch_all_denies_uninstalled_ability_test() {
  let handler = capability.catch_all()
  let result = ffi_rescue(fn() { handler(0, [to_dynamic("x")], fn(d) { d }) })
  let assert Error(reason) = result
  string.contains(reason, "capability_denied") |> should.be_true
}
