import gleam/bit_array
import gleamunison/crypto.{
  type Argon2Params, Argon2Params, argon2id, blake2b_hex, secure_compare,
}

// RFC 7693 Appendix A: BLAKE2b-512("abc")
pub fn blake2b_512_abc_test() {
  let assert Ok(hex) = blake2b_hex(<<"abc":utf8>>, 64)
  let assert True =
    hex
    == "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923"
}

// Cross-check our Blake2b against OTP's native blake2b at 64 bytes.
pub fn blake2b_64_matches_otp_test() {
  let inputs = [
    <<"":utf8>>,
    <<"x":utf8>>,
    <<"the quick brown fox jumps over the lazy dog":utf8>>,
  ]
  check_otp_parity(inputs)
}

@external(erlang, "gleamunison_ffi_test", "otp_blake2b64")
fn otp_blake2b(data: BitArray) -> BitArray

fn check_otp_parity(inputs: List(BitArray)) -> Nil {
  case inputs {
    [] -> Nil
    [data, ..rest] -> {
      let assert Ok(mine_bin) = crypto.blake2b(data, 64)
      let otp = otp_blake2b(data)
      let assert True = mine_bin == otp
      let assert True = bit_array.byte_size(mine_bin) == 64
      check_otp_parity(rest)
    }
  }
}

fn rfc9106_params() -> Argon2Params {
  Argon2Params(
    password: <<
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
    >>,
    salt: <<2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2>>,
    secret: <<3, 3, 3, 3, 3, 3, 3, 3>>,
    ad: <<4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4>>,
    passes: 3,
    memory_kib: 32,
    parallelism: 4,
    tag_length: 32,
  )
}

// RFC 9106 section 5.3: Argon2id version 19, m=32 KiB, t=3, p=4
pub fn argon2id_rfc9106_vector_test() {
  let assert Ok(tag) = argon2id(rfc9106_params())
  let hex = crypto.to_hex(tag)
  let assert True =
    hex == "0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659"
}

// Same input, same tag (deterministic); different password, different tag.
pub fn argon2id_deterministic_and_sensitive_test() {
  let params = rfc9106_params()
  let assert Ok(a) = argon2id(params)
  let assert Ok(b) = argon2id(params)
  let assert True = secure_compare(a, b)
  let params2 = Argon2Params(..params, password: <<9, 9, 9, 9>>)
  let assert Ok(c) = argon2id(params2)
  let assert False = secure_compare(a, c)
}

// H0 intermediate from RFC 9106 5.3: validates H^64 construction in context.
pub fn argon2id_h0_intermediate_test() {
  let assert Ok(hex) = crypto.argon2_h0_debug_hex(rfc9106_params())
  let assert True =
    hex
    == "2889de487eb42ae500c0007ed9252f1069eadec40d5765b485de6dc2437a67b8546a2f0acc1a0882db8fcf74714b472e94df421a5da1112ffa11434370a1e997"
}
