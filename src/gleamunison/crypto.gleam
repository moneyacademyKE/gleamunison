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
fn ffi_hmac(algo: String, key: BitArray, data: BitArray) -> Result(BitArray, String)

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

pub fn hash(algo: HashAlgorithm, data: BitArray) -> Result(BitArray, CryptoError) {
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

pub fn hash_hex(algo: HashAlgorithm, data: BitArray) -> Result(String, CryptoError) {
  case hash(algo, data) {
    Ok(digest) -> Ok(ffi_hash_to_hex(digest))
    Error(e) -> Error(e)
  }
}
