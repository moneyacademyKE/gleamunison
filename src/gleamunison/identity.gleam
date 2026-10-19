import gleam/result
import gleam/string

/// Opaque hash type. No access to the inner bytes outside this module.
pub opaque type Hash {
  Hash(contents: BitArray)
}

/// A content-addressed reference to a definition.
pub type DefinitionRef {
  Ref(hash: Hash)
}

/// Local variable binding using de Bruijn indices.
pub type LocalVar {
  Local(index: Int)
}

// --- FFI declarations ---

@external(erlang, "gleamunison_ffi", "hash_bytes")
fn ffi_hash_bytes(_bytes: BitArray) -> BitArray

@external(erlang, "gleamunison_ffi", "hex_to_bytes")
pub fn hex_to_bytes(hex: String) -> Result(BitArray, String)

/// Parse an external SHA-256 reference before it reaches storage or transport.
pub fn parse_ref_hex(hex: String) -> Result(DefinitionRef, String) {
  case string.length(hex) == 64 {
    False -> Error("invalid reference: expected 64 hexadecimal SHA-256 digits")
    True -> {
      use bytes <- result.try(hex_to_bytes(hex))
      Ok(Ref(hash_from_bytes(bytes)))
    }
  }
}

@external(erlang, "gleamunison_ffi", "hash_equal")
fn ffi_hash_equal(_a: BitArray, _b: BitArray) -> Bool

@external(erlang, "gleamunison_ffi", "hash_to_hex")
fn ffi_hash_to_hex(_bytes: BitArray) -> List(String)

// --- Construction (module-private) ---

pub fn hash_from_bytes(contents: BitArray) -> Hash {
  Hash(contents)
}

pub fn hash_to_bytes(h: Hash) -> BitArray {
  let Hash(contents) = h
  contents
}

/// Compare two hashes for equality.
pub fn hash_equal(a: Hash, b: Hash) -> Bool {
  ffi_hash_equal(hash_to_bytes(a), hash_to_bytes(b))
}

/// Compute a SHA-256 hash from arbitrary bytes.
pub fn hash_bytes(contents: BitArray) -> Hash {
  Hash(ffi_hash_bytes(contents))
}

/// Extract the index from a LocalVar (de Bruijn index).
pub fn local_var_index(lv: LocalVar) -> Int {
  let Local(index) = lv
  index
}

/// Produce a hex string for display/debugging.
pub fn hash_to_debug_string(h: Hash) -> String {
  let parts = ffi_hash_to_hex(hash_to_bytes(h))
  string.join(parts, "")
}

/// Produce a short hash prefix for display.
pub fn hash_to_short_string(h: Hash) -> String {
  let s = hash_to_debug_string(h)
  string.slice(s, 0, 12)
}
