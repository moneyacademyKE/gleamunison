//// The evidence turnstile: a pure gate between "code exists" and "code
//// ships". Every definition carries a content hash; every test run attests
//// evidence onto that hash. `check` answers one question: which of these
//// hashes have a passing Test attestation? Publishing composes this gate
//// with a manifest write — no evidence, no entry.

import gleam/list
import gleam/string
import gleamunison/evidence
import gleamunison/storage.{type StorageAdapter}

/// Check #(name, subject_hex) pairs against the evidence store.
/// Ok(all names) when every gated def has a passing Test attestation;
/// Error(just the unevidenced names) otherwise. `test_` defs produce
/// evidence, they do not consume it — gating them would be a
/// chicken-and-egg loop, so they pass by construction.
pub fn check(
  adapter: StorageAdapter,
  defs: List(#(String, String)),
) -> Result(List(String), List(String)) {
  let gated = list.filter(defs, fn(d) { !string.starts_with(d.0, "test_") })
  let missing =
    list.filter_map(gated, fn(d) {
      case evidence.verified(adapter, d.1, evidence.Test) {
        True -> Error(Nil)
        False -> Ok(d.0)
      }
    })
  case missing {
    [] -> Ok(list.map(defs, fn(d) { d.0 }))
    _ -> Error(missing)
  }
}
