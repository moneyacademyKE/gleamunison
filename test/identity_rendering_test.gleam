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

// ── Ported from crypto_argon2_test (bk-eca5): production crypto surface ──
// to_hex was already pinned above; the argon2/blake2b island carried the
// constant-time compare contract, so it moves here unchanged.

// The one-owner constant-time secret compare (bk-49ec), used by the HTTP
// bearer gate and the TCP sync handshake: sha256-then-compare means tokens
// of UNEQUAL length take the same fixed-digest path instead of a
// short-circuiting size check.
@external(erlang, "gleamunison_ffi_test", "constant_time_equal_probe")
fn constant_time_equal_probe(a: BitArray, b: BitArray) -> Bool

pub fn constant_time_equal_unequal_length_tokens_test() {
  // unequal length, unequal content
  let assert False =
    constant_time_equal_probe(<<"a-longer-secret-token":utf8>>, <<"short":utf8>>)
  // unequal length, one side empty (the missing-Authorization-header path)
  let assert False = constant_time_equal_probe(<<"secret":utf8>>, <<"":utf8>>)
  let assert True = constant_time_equal_probe(<<"":utf8>>, <<"":utf8>>)
  // equal length, equal content
  let assert True =
    constant_time_equal_probe(<<"same-token":utf8>>, <<"same-token":utf8>>)
  // equal length, different content
  let assert False =
    constant_time_equal_probe(<<"token-a":utf8>>, <<"token-b":utf8>>)
  // unequal length where the longer token starts with the shorter one —
  // a prefix must never pass
  let assert False =
    constant_time_equal_probe(<<"token":utf8>>, <<"token-extended":utf8>>)
}

// secure_compare is the equal-size constant-time compare under the
// arbitrary-length owner above (crypto_argon2_test pinned it on argon2
// tags; plain tokens carry the same contract).
pub fn secure_compare_matches_and_rejects_test() {
  let assert True =
    crypto.secure_compare(<<"same-tag":utf8>>, <<"same-tag":utf8>>)
  let assert False =
    crypto.secure_compare(<<"token-a":utf8>>, <<"token-b":utf8>>)
  // unequal lengths never enter the constant-time path: False, never a crash
  let assert False =
    crypto.secure_compare(<<"short":utf8>>, <<"a-longer-secret-token":utf8>>)
}

// HMAC-SHA256 known-answer vector (RFC 4231 test case 1). The argon2 test
// file never pinned hmac; the evidence-signing primitive gets its first
// direct assertion here so the port leaves no named surface uncovered.
pub fn hmac_sha256_rfc4231_case1_test() {
  let key = <<
    11,
    11,
    11,
    11,
    11,
    11,
    11,
    11,
    11,
    11,
    11,
    11,
    11,
    11,
    11,
    11,
    11,
    11,
    11,
    11,
  >>
  let assert Ok(mac) = crypto.hmac_sha256(key, <<"Hi There":utf8>>)
  crypto.to_hex(mac)
  |> should.equal(
    "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
  )
}
