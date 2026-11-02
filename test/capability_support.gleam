//// Test-side capability scaffolding (bk-b282): the frame→key derivation,
//// guard rewrite, and catch-all bottom handler had zero production callers
//// outside their own module — production builds policies through
//// sandbox_policy.local/untrusted, and nothing in src calls guard_frames.
//// The functions stay shape-identical; the assertions that pin them live in
//// test/ and now so does the code they call. capability.check keeps its
//// production home (denies-by-default is the documented policy surface).

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/list
import gleamunison/capability
import gleamunison/effects.{type HandlerFrame, HandlerFrame}

@external(erlang, "gleamunison_ffi", "deny_capability")
fn deny_capability(key: String, op: Int) -> Dynamic

/// The ability key a frame serves (the runtime's own key derivation).
pub fn frame_key(frame: HandlerFrame) -> String {
  effects.ability_key(frame.ability)
}

/// Rewrite frames under a policy: allowed abilities pass through untouched;
/// denied abilities keep their shape but every op raises a structured
/// {capability_denied, key, op} instead of running. A denied op is a loud,
/// matchable failure — never a fabricated result, never a silent skip.
pub fn guard_frames(
  policy: capability.Policy,
  frames: List(HandlerFrame),
) -> List(HandlerFrame) {
  list.map(frames, fn(frame) {
    let key = frame_key(frame)
    case capability.allows(policy, key) {
      True -> frame
      False ->
        HandlerFrame(
          ability: frame.ability,
          ops: dict.map_values(frame.ops, fn(op_idx, _inner) {
            fn(_args: List(Dynamic), _cont: fn(Dynamic) -> Dynamic) -> Dynamic {
              deny_capability(key, op_idx)
            }
          }),
        )
    }
  })
}

/// A bare catch-all handler for the bottom of the stack: any ability with
/// no installed frame raises capability_denied instead of the runtime's
/// unhandled_ability. Install last so allowed frames always win.
pub fn catch_all() -> fn(Int, List(Dynamic), fn(Dynamic) -> Dynamic) -> Dynamic {
  fn(op_idx: Int, _args: List(Dynamic), _cont: fn(Dynamic) -> Dynamic) -> Dynamic {
    deny_capability("m_unhandled", op_idx)
  }
}
