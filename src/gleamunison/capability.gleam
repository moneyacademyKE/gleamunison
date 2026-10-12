import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/list
import gleamunison/effects.{type HandlerFrame, HandlerFrame}

/// A sandbox policy: the exact set of abilities a program may use, named
/// by their content-addressed keys ("m_" + hash suffix). Anything not
/// listed is denied — deny-by-default, never allow-by-default.
pub type Policy {
  Policy(allow: List(String))
}

pub fn allow(keys: List(String)) -> Policy {
  Policy(allow: keys)
}

/// The ability key a frame serves (the runtime's own key derivation).
pub fn frame_key(frame: HandlerFrame) -> String {
  effects.ability_key(frame.ability)
}

pub fn allows(policy: Policy, key: String) -> Bool {
  list.contains(policy.allow, key)
}

@external(erlang, "gleamunison_ffi", "deny_capability")
fn deny_capability(key: String, op: Int) -> Dynamic

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn to_dynamic(val: a) -> Dynamic

/// Pre-flight: which abilities in these frames does the policy deny?
/// Ok(Nil) means every frame is allowed.
pub fn check(
  policy: Policy,
  frames: List(HandlerFrame),
) -> Result(Nil, List(String)) {
  let denied =
    list.filter_map(frames, fn(frame) {
      let key = frame_key(frame)
      case allows(policy, key) {
        True -> Error(Nil)
        False -> Ok(key)
      }
    })
  case denied {
    [] -> Ok(Nil)
    _ -> Error(denied)
  }
}

/// Rewrite frames under a policy: allowed abilities pass through untouched;
/// denied abilities keep their shape but every op raises a structured
/// {capability_denied, key, op} instead of running. A denied op is a loud,
/// matchable failure — never a fabricated result, never a silent skip.
pub fn guard_frames(
  policy: Policy,
  frames: List(HandlerFrame),
) -> List(HandlerFrame) {
  list.map(frames, fn(frame) {
    let key = frame_key(frame)
    case allows(policy, key) {
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

/// Run an entry thunk under a policy: allowed frames execute, denied
/// frames raise structured denials, and the catch-all sits innermost so
/// ambient authority (any ability without an explicit allowed frame) is
/// impossible by construction.
pub fn run_scoped(
  policy: Policy,
  frames: List(HandlerFrame),
  entry: fn() -> Dynamic,
) -> Dynamic {
  let guarded = guard_frames(policy, frames)
  let innermost = fn() { handle_any(to_dynamic(catch_all()), entry) }
  list.fold_right(guarded, innermost, fn(thunk, frame) {
    let key = frame_key(frame)
    fn() { handle_any(to_dynamic(#(key, frame.ops)), thunk) }
  })()
}

@external(erlang, "gleamunison_effets", "handle_comp")
fn handle_any(handler: Dynamic, thunk: fn() -> Dynamic) -> Dynamic
