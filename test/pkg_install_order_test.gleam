//// An install asks two questions: does the store hold this manifest, and may
//// this node admit it? Existence comes first. Asking the evidence policy before
//// existence told a caller to configure a signing key when there was nothing to
//// verify — a resolution failure wearing a policy refusal's clothes, and the
//// wrong exit code for a script.

import gleam/string
import gleamunison/pkg
import gleamunison/storage
import gleeunit/should

@external(erlang, "gleamunison_ffi_test", "set_env")
fn set_env(key: String, value: String) -> Nil

@external(erlang, "gleamunison_ffi_test", "unset_env")
fn unset_env(key: String) -> Nil

const absent_hex =
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

/// A fresh store, no signing key: the honest answer is that the manifest is
/// absent, not that the node needs a key to verify something it does not have.
pub fn absent_manifest_is_named_before_policy_test() {
  unset_env("GLEAMUNISON_EVIDENCE_SIGNING_KEY")
  let adapter = storage.inmemory()
  case pkg.install_from_store_production(adapter, absent_hex, "main") {
    Ok(_) -> panic as "installed a manifest from an empty store"
    Error(message) -> {
      string.contains(message, "manifest not found")
      |> should.be_true
      string.contains(message, "SIGNING_KEY")
      |> should.be_false
    }
  }
}

/// The same ordering with a key configured: still about the missing manifest.
pub fn absent_manifest_is_named_with_a_key_test() {
  set_env("GLEAMUNISON_EVIDENCE_SIGNING_KEY", "k")
  let adapter = storage.inmemory()
  let result = pkg.install_from_store_production(adapter, absent_hex, "main")
  unset_env("GLEAMUNISON_EVIDENCE_SIGNING_KEY")
  case result {
    Ok(_) -> panic as "installed a manifest from an empty store"
    Error(message) ->
      string.contains(message, "manifest not found")
      |> should.be_true
  }
}

/// A malformed hash is the caller's mistake, and it is not a missing manifest:
/// the hex check comes first.
pub fn malformed_hash_is_refused_before_lookup_test() {
  unset_env("GLEAMUNISON_EVIDENCE_SIGNING_KEY")
  let adapter = storage.inmemory()
  case pkg.install_from_store_production(adapter, "not-a-hash", "main") {
    Ok(_) -> panic as "accepted a malformed manifest hash"
    Error(message) ->
      string.contains(message, "invalid reference")
      |> should.be_true
  }
}
