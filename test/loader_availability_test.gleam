//// Availability is what lets a definition load without a store entry: the
//// genesis builtins and registered jets are already in the runtime.

import gleamunison/genesis
import gleamunison/identity.{Ref, hash_bytes, hash_from_bytes}
import gleamunison/loader
import gleeunit/should

pub fn a_genesis_builtin_is_already_available_test() {
  loader.module_available(genesis.builtin_int_add()) |> should.be_true
}

pub fn an_unknown_ref_is_not_available_test() {
  loader.module_available(Ref(hash_bytes(<<"absent-definition">>)))
  |> should.be_false
}

pub fn a_jet_ref_loads_without_the_store_test() {
  let fib = Ref(hash_from_bytes(<<0x7b:256>>))
  loader.module_available(fib) |> should.be_false
  let assert Ok(_) = loader.ensure_loaded_jet(loader.new_loader(), fib)
  loader.module_available(fib) |> should.be_true
}

pub fn a_non_jet_ref_is_refused_by_the_jet_path_test() {
  let ref = Ref(hash_bytes(<<"not-a-jet">>))
  let assert Error(#(_, loader.CompileFailed(got, _))) =
    loader.ensure_loaded_jet(loader.new_loader(), ref)
  got |> should.equal(ref)
}
