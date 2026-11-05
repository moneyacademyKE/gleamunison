import gleam/result

pub type CryptoError {
  InvalidInput(reason: String)
}

@external(erlang, "gleamunison_crypto", "hmac")
fn ffi_hmac(
  algo: String,
  key: BitArray,
  data: BitArray,
) -> Result(BitArray, String)

@external(erlang, "gleamunison_crypto", "hash_to_hex")
fn ffi_hash_to_hex(bytes: BitArray) -> String

pub fn hmac_sha256(
  key: BitArray,
  data: BitArray,
) -> Result(BitArray, CryptoError) {
  ffi_hmac("sha256", key, data)
  |> result.map_error(fn(e) { InvalidInput(e) })
}

/// Hex-encode raw bytes (no hashing).
pub fn to_hex(bytes: BitArray) -> String {
  ffi_hash_to_hex(bytes)
}

@external(erlang, "gleamunison_crypto", "secure_compare")
fn ffi_secure_compare(a: BitArray, b: BitArray) -> Bool

/// Constant-time comparison (for tag verification).
pub fn secure_compare(a: BitArray, b: BitArray) -> Bool {
  ffi_secure_compare(a, b)
}
