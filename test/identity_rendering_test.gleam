import gleam/string
import gleamunison/compile
import gleamunison/effects
import gleamunison/identity.{Ref, hash_bytes}
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn ref_hex_is_the_canonical_full_hash_test() {
  let ref = Ref(hash_bytes(<<"canonical-ref-rendering">>))
  identity.ref_hex(ref)
  |> should.equal(case ref {
    Ref(hash) -> identity.hash_to_debug_string(hash)
  })
  identity.parse_ref_hex(identity.ref_hex(ref)) |> should.equal(Ok(ref))
}

pub fn runtime_module_name_has_one_canonical_suffix_test() {
  let ref = Ref(hash_bytes(<<"canonical-runtime-module">>))
  let expected = "m_" <> string.drop_start(identity.ref_hex(ref), 56)
  identity.runtime_module_name(ref) |> should.equal(expected)
  compile.module_name_for(ref) |> should.equal(expected)
  effects.ability_key(ref) |> should.equal(expected)
}
