//// Genesis builtins ship as compiled modules, so they need no store entry.
//// Unknown refs have no hidden runtime fallback.

import gleamunison/genesis
import gleamunison/identity.{Ref, hash_bytes}
import gleamunison/loader
import gleeunit/should

pub fn a_genesis_builtin_is_already_available_test() {
  loader.module_available(genesis.builtin_int_add()) |> should.be_true
}

pub fn describe_load_errors_test() {
  let ref = Ref(hash_bytes(<<"definition">>))

  loader.describe(loader.CompileFailed(ref, "elaborate failed"))
  |> should.equal("compile failed: elaborate failed")

  loader.describe(loader.LoadFailed(ref, "beam missing"))
  |> should.equal("load failed: beam missing")
}

pub fn an_unknown_ref_is_not_available_test() {
  loader.module_available(Ref(hash_bytes(<<"absent-definition">>)))
  |> should.be_false
}
