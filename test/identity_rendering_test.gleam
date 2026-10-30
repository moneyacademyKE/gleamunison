import gleam/string
import gleamunison/compile
import gleamunison/crypto
import gleamunison/effects
import gleamunison/identity.{Ref, hash_bytes, hash_from_bytes}
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

pub fn short_ref_hex_delegates_to_the_hash_renderer_test() {
  let ref = Ref(hash_bytes(<<"canonical-short-ref-rendering">>))
  let expected = case ref {
    Ref(hash) -> identity.hash_to_short_string(hash)
  }
  identity.short_ref_hex(ref) |> should.equal(expected)
  string.length(expected) |> should.equal(12)
}

pub fn short_hash_hex_uses_the_same_display_rule_test() {
  let ref = Ref(hash_bytes(<<"canonical-short-hash-rendering">>))
  identity.short_hash_hex(identity.ref_hex(ref))
  |> should.equal(identity.short_ref_hex(ref))
}

pub fn runtime_module_name_has_one_canonical_suffix_test() {
  let ref = Ref(hash_bytes(<<"canonical-runtime-module">>))
  let expected = "m_" <> string.drop_start(identity.ref_hex(ref), 56)
  identity.runtime_module_name(ref) |> should.equal(expected)
  compile.module_name_for(ref) |> should.equal(expected)
  effects.ability_key(ref) |> should.equal(expected)
}

pub fn ref_hex_pins_the_canonical_lowercase_bytes_test() {
  // One fixed digest spanning 0x00, 0x0a, 0xff and the nibble boundaries
  // pins lowercase, zero-padding and width 64 in a single literal. These
  // bytes are load-bearing on disk: ref_hex is the canonical external ref
  // representation, runtime_module_name slices its tail, and DETS/Mnesia
  // table atoms derive through the same encoder. The expected value was
  // captured from BOTH pre-unification Erlang encoders, which were proven
  // byte-identical over this digest, 1000 random binaries and the empty
  // binary before the ffi copy was deleted (bk-bd8f).
  let digest = <<
    0,
    10,
    255,
    1,
    254,
    15,
    16,
    240,
    0,
    170,
    85,
    255,
    128,
    127,
    9,
    246,
    0,
    0,
    255,
    255,
    16,
    1,
    238,
    23,
    64,
    4,
    12,
    3,
    8,
    2,
    0,
    1,
  >>
  let expected =
    "000aff01fe0f10f000aa55ff807f09f60000ffff1001ee1740040c0308020001"
  let ref = Ref(hash_from_bytes(digest))
  identity.ref_hex(ref) |> should.equal(expected)
  string.length(identity.ref_hex(ref)) |> should.equal(64)
  // ref_hex and crypto.to_hex are now the SAME encoder, not two that agree.
  crypto.to_hex(digest) |> should.equal(expected)
}
