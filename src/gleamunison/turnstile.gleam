//// The evidence turnstile: a pure gate between "code exists" and "code
//// ships". Every definition carries a content hash; every test run attests
//// evidence onto that hash. `check` answers one question: which of these
//// defs are evidenced? Pure defs require a passing Test attestation;
//// effectful defs (non-empty requirement row) may alternatively carry a
//// human Io attestation — the only honest evidence for IO a suite cannot
//// drive. Io never substitutes for Test on pure defs: tests are cheap
//// there, so they are mandatory. Publishing composes this gate with a
//// manifest write — no evidence, no entry.

import gleam/list
import gleam/string
import gleamunison/evidence
import gleamunison/storage.{type StorageAdapter}

/// Check #(name, subject_hex, effectful) triples against the evidence
/// store. Ok(all names) when every gated def is evidenced per the rule
/// above; Error(just the unevidenced names) otherwise. `test_` defs
/// produce evidence, they do not consume it — gating them would be a
/// chicken-and-egg loop, so they pass by construction.
pub fn check(
  adapter: StorageAdapter,
  defs: List(#(String, String, Bool)),
) -> Result(List(String), List(String)) {
  let gated = list.filter(defs, fn(d) { !string.starts_with(d.0, "test_") })
  let missing =
    list.filter_map(gated, fn(d) {
      case admitted(adapter, d.1, d.2) {
        True -> Error(Nil)
        False -> Ok(d.0)
      }
    })
  case missing {
    [] -> Ok(list.map(defs, fn(d) { d.0 }))
    _ -> Error(missing)
  }
}

/// The gate rule for one def: Test evidence always admits; Io attestation
/// admits only when the def's inferred requirement row is non-empty.
fn admitted(adapter: StorageAdapter, subject: String, effectful: Bool) -> Bool {
  evidence.verified(adapter, subject, evidence.Test)
  || { effectful && evidence.verified(adapter, subject, evidence.Io) }
}
