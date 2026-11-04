//// Genesis builtins ship as compiled modules, so they need no store entry.
//// Unknown refs have no hidden runtime fallback.

import gleam/list
import gleamunison/bootstrap_terms
import gleamunison/genesis
import gleamunison/identity.{Ref, hash_bytes}
import gleamunison/loader
import gleeunit/should

pub fn a_genesis_builtin_is_already_available_test() {
  loader.module_available(genesis.builtin_int_add()) |> should.be_true
}

pub fn every_genesis_builtin_module_is_available_test() {
  // entries() is the exhaustive production table (is_host_ref reads it), so
  // this pins every precompiled m_<hex> module the runtime can name. A
  // failure lists the builtins whose compiled module is missing.
  let unavailable =
    bootstrap_terms.entries()
    |> list.filter(fn(entry) {
      let #(_, ref, _) = entry
      !loader.module_available(ref)
    })
    |> list.map(fn(entry) {
      let #(name, _, _) = entry
      name
    })
  should.equal(unavailable, [])
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
