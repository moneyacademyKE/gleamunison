import gleam/result

pub type HashAlgorithm {
  Sha256
  Sha512
  Md5
}

pub type CryptoError {
  InvalidInput(reason: String)
}

@external(erlang, "gleamunison_crypto", "hash")
fn ffi_hash(algo: String, data: BitArray) -> Result(BitArray, String)

@external(erlang, "gleamunison_crypto", "hmac")
fn ffi_hmac(
  algo: String,
  key: BitArray,
  data: BitArray,
) -> Result(BitArray, String)

@external(erlang, "gleamunison_crypto", "random_bytes")
fn ffi_random_bytes(n: Int) -> BitArray

@external(erlang, "gleamunison_crypto", "hash_to_hex")
fn ffi_hash_to_hex(bytes: BitArray) -> String

fn algo_to_string(algo: HashAlgorithm) -> String {
  case algo {
    Sha256 -> "sha256"
    Sha512 -> "sha512"
    Md5 -> "md5"
  }
}

pub fn hash(
  algo: HashAlgorithm,
  data: BitArray,
) -> Result(BitArray, CryptoError) {
  ffi_hash(algo_to_string(algo), data)
  |> result.map_error(fn(e) { InvalidInput(e) })
}

pub fn hmac(
  algo: HashAlgorithm,
  key: BitArray,
  data: BitArray,
) -> Result(BitArray, CryptoError) {
  ffi_hmac(algo_to_string(algo), key, data)
  |> result.map_error(fn(e) { InvalidInput(e) })
}

pub fn random_bytes(n: Int) -> BitArray {
  ffi_random_bytes(n)
}

pub fn hash_hex(
  algo: HashAlgorithm,
  data: BitArray,
) -> Result(String, CryptoError) {
  case hash(algo, data) {
    Ok(digest) -> Ok(ffi_hash_to_hex(digest))
    Error(e) -> Error(e)
  }
}

/// Hex-encode raw bytes (no hashing).
pub fn to_hex(bytes: BitArray) -> String {
  ffi_hash_to_hex(bytes)
}

// ── BLAKE2b with variable digest length (RFC 7693) ─────────────────────

@external(erlang, "gleamunison_crypto", "blake2b")
fn ffi_blake2b(data: BitArray, out_len: Int) -> Result(BitArray, String)

pub fn blake2b(data: BitArray, out_len: Int) -> Result(BitArray, CryptoError) {
  ffi_blake2b(data, out_len)
  |> result.map_error(fn(e) { InvalidInput(e) })
}

pub fn blake2b_hex(
  data: BitArray,
  out_len: Int,
) -> Result(String, CryptoError) {
  case blake2b(data, out_len) {
    Ok(d) -> Ok(ffi_hash_to_hex(d))
    Error(e) -> Error(e)
  }
}

// ── Argon2id password hashing (RFC 9106) ────────────────────────────────

pub type Argon2Params {
  Argon2Params(
    password: BitArray,
    salt: BitArray,
    secret: BitArray,
    ad: BitArray,
    passes: Int,
    memory_kib: Int,
    parallelism: Int,
    tag_length: Int,
  )
}

@external(erlang, "gleamunison_crypto", "argon2id")
fn ffi_argon2id(
  password: BitArray,
  salt: BitArray,
  secret: BitArray,
  ad: BitArray,
  passes: Int,
  memory_kib: Int,
  parallelism: Int,
  tag_length: Int,
) -> Result(BitArray, String)

pub fn argon2id(params: Argon2Params) -> Result(BitArray, CryptoError) {
  ffi_argon2id(
    params.password,
    params.salt,
    params.secret,
    params.ad,
    params.passes,
    params.memory_kib,
    params.parallelism,
    params.tag_length,
  )
  |> result.map_error(fn(e) { InvalidInput(e) })
}

@external(erlang, "gleamunison_crypto", "argon2_h0")
fn ffi_argon2_h0(
  password: BitArray,
  salt: BitArray,
  secret: BitArray,
  ad: BitArray,
  passes: Int,
  memory_kib: Int,
  parallelism: Int,
  tag_length: Int,
) -> BitArray

/// Test support: H0 intermediate for RFC 9106 section 5.3 cross-checks.
/// Never call on production password material.
pub fn argon2_h0_debug_hex(
  params: Argon2Params,
) -> Result(String, CryptoError) {
  Ok(
    ffi_hash_to_hex(ffi_argon2_h0(
      params.password,
      params.salt,
      params.secret,
      params.ad,
      params.passes,
      params.memory_kib,
      params.parallelism,
      params.tag_length,
    )),
  )
}

@external(erlang, "gleamunison_crypto", "secure_compare")
fn ffi_secure_compare(a: BitArray, b: BitArray) -> Bool

/// Constant-time comparison (for tag verification).
pub fn secure_compare(a: BitArray, b: BitArray) -> Bool {
  ffi_secure_compare(a, b)
}
