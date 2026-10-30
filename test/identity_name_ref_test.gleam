//// The name->ref derivation has one owner, so these tests pin the two things
//// that matter: the exact bytes it produces, and that the two public copies
//// demoted to delegates still return what they returned when each held its own
//// derivation. A changed derivation orphans every definition already stored
//// under the old one, and it does so silently, which is why the hex is written
//// out here rather than recomputed from the same code under test.

import gleam/list
import gleamunison/identity
import gleamunison/pipeline
import gleamunison/repl_eval
import gleeunit/should

/// SHA-256 of the name's UTF-8 bytes, rendered as the canonical hex. These are
/// the on-disk and on-wire identity of every named definition.
pub fn the_name_hash_bytes_are_pinned_test() {
  identity.ref_hex(identity.name_ref("Console"))
  |> should.equal(
    "29a40861bafe31e774190c795fc6fe4b8c012fea4707010f4102e52d74eafa15",
  )

  identity.ref_hex(identity.name_ref("Db"))
  |> should.equal(
    "0a276e36c919a771e9828242ea83431ceb7d7a8fb3804f75f010b4d555b9371b",
  )

  identity.ref_hex(identity.name_ref("+"))
  |> should.equal(
    "a318c24216defe206feeb73ef5be00033fa9c4a74d0b967f6532a26ca5906d3b",
  )

  // The empty name hashes to the empty-input SHA-256, so the derivation adds
  // nothing to the bytes it is given.
  identity.ref_hex(identity.name_ref(""))
  |> should.equal(
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
}

/// repl_eval and pipeline each used to carry their own copy of the derivation
/// (elaborate's was private, forced by repl_eval importing elaborate, and is
/// covered by the elaboration suite). Both keep their public contract.
pub fn the_demoted_delegates_still_agree_with_identity_test() {
  ["Console", "Db", "+", "self", "list-map", "", "a-name-with-dashes"]
  |> list.each(fn(name) {
    repl_eval.ref_for_name(name) |> should.equal(identity.name_ref(name))
    pipeline.ref_for_name(name) |> should.equal(identity.name_ref(name))
  })
}

/// The runtime module name is cut from the same ref, so it moves only if the
/// pinned hash moves: the loader and the compiled beams keep agreeing.
pub fn the_runtime_module_name_follows_the_pinned_hash_test() {
  identity.runtime_module_name(identity.name_ref("Console"))
  |> should.equal("m_74eafa15")
}
