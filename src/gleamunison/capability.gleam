import gleam/list
import gleamunison/effects.{type HandlerFrame}

/// A sandbox policy: the exact set of abilities a program may use, named
/// by their content-addressed keys ("m_" + hash suffix). Anything not
/// listed is denied — deny-by-default, never allow-by-default.
pub type Policy {
  Policy(allow: List(String))
}

pub fn allow(keys: List(String)) -> Policy {
  Policy(allow: keys)
}

pub fn allows(policy: Policy, key: String) -> Bool {
  list.contains(policy.allow, key)
}

/// Pre-flight: which abilities in these frames does the policy deny?
/// Ok(Nil) means every frame is allowed.
pub fn check(
  policy: Policy,
  frames: List(HandlerFrame),
) -> Result(Nil, List(String)) {
  let denied =
    list.filter_map(frames, fn(frame) {
      let key = effects.ability_key(frame.ability)
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
