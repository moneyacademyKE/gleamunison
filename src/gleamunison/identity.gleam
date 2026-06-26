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
pub fn hex_to_bytes(hex: String) -> BitArray

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

/// Compute a hash from arbitrary bytes. Uses phash2 (fast, non-crypto).
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

// --- Genesis: well-known builtin hashes ---
// Placeholder hashes — actual values depend on genesis block content.

pub fn builtin_int_add() -> DefinitionRef {
  Ref(Hash(<<1:32>>))
}

pub fn builtin_io_read_line() -> DefinitionRef {
  Ref(Hash(<<2:32>>))
}
