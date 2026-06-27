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
  Ref(Hash(<<1:256>>))
}

pub fn builtin_io_read_line() -> DefinitionRef {
  Ref(Hash(<<2:256>>))
}

pub fn builtin_state_get() -> DefinitionRef {
  Ref(Hash(<<3:256>>))
}

pub fn builtin_state_put() -> DefinitionRef {
  Ref(Hash(<<4:256>>))
}

pub fn builtin_process_spawn() -> DefinitionRef {
  Ref(Hash(<<5:256>>))
}

pub fn builtin_process_self() -> DefinitionRef {
  Ref(Hash(<<6:256>>))
}

pub fn builtin_process_send() -> DefinitionRef {
  Ref(Hash(<<7:256>>))
}

pub fn builtin_process_recv() -> DefinitionRef {
  Ref(Hash(<<8:256>>))
}

pub fn builtin_timer_sleep() -> DefinitionRef {
  Ref(Hash(<<9:256>>))
}

pub fn builtin_timer_now() -> DefinitionRef {
  Ref(Hash(<<10:256>>))
}

// Arithmetic (101-102)
pub fn builtin_sub() -> DefinitionRef { Ref(Hash(<<11:256>>)) }
pub fn builtin_mul() -> DefinitionRef { Ref(Hash(<<12:256>>)) }
pub fn builtin_div() -> DefinitionRef { Ref(Hash(<<13:256>>)) }
pub fn builtin_mod() -> DefinitionRef { Ref(Hash(<<14:256>>)) }

// Comparison (103)
pub fn builtin_eq() -> DefinitionRef { Ref(Hash(<<15:256>>)) }
pub fn builtin_lt() -> DefinitionRef { Ref(Hash(<<16:256>>)) }
pub fn builtin_gt() -> DefinitionRef { Ref(Hash(<<17:256>>)) }

// Boolean (104)
pub fn builtin_and() -> DefinitionRef { Ref(Hash(<<18:256>>)) }
pub fn builtin_or() -> DefinitionRef { Ref(Hash(<<19:256>>)) }
pub fn builtin_not() -> DefinitionRef { Ref(Hash(<<20:256>>)) }

// String ops (151-160)
pub fn builtin_string_concat() -> DefinitionRef { Ref(Hash(<<21:256>>)) }
pub fn builtin_string_length() -> DefinitionRef { Ref(Hash(<<22:256>>)) }
pub fn builtin_string_contains() -> DefinitionRef { Ref(Hash(<<23:256>>)) }
pub fn builtin_string_slice() -> DefinitionRef { Ref(Hash(<<24:256>>)) }
pub fn builtin_string_upcase() -> DefinitionRef { Ref(Hash(<<25:256>>)) }
pub fn builtin_string_downcase() -> DefinitionRef { Ref(Hash(<<26:256>>)) }
pub fn builtin_string_replace() -> DefinitionRef { Ref(Hash(<<27:256>>)) }
pub fn builtin_string_split() -> DefinitionRef { Ref(Hash(<<28:256>>)) }
pub fn builtin_string_trim() -> DefinitionRef { Ref(Hash(<<29:256>>)) }
pub fn builtin_string_to_int() -> DefinitionRef { Ref(Hash(<<30:256>>)) }

// List ops (161-170)
pub fn builtin_list_length() -> DefinitionRef { Ref(Hash(<<31:256>>)) }
pub fn builtin_list_reverse() -> DefinitionRef { Ref(Hash(<<32:256>>)) }
pub fn builtin_list_map() -> DefinitionRef { Ref(Hash(<<33:256>>)) }
pub fn builtin_list_filter() -> DefinitionRef { Ref(Hash(<<34:256>>)) }
pub fn builtin_list_fold() -> DefinitionRef { Ref(Hash(<<35:256>>)) }
pub fn builtin_list_append() -> DefinitionRef { Ref(Hash(<<36:256>>)) }
pub fn builtin_list_flatten() -> DefinitionRef { Ref(Hash(<<37:256>>)) }
pub fn builtin_list_member() -> DefinitionRef { Ref(Hash(<<38:256>>)) }
pub fn builtin_list_range() -> DefinitionRef { Ref(Hash(<<39:256>>)) }
pub fn builtin_list_sort() -> DefinitionRef { Ref(Hash(<<40:256>>)) }

// Data structures (171-180)
pub fn builtin_pair() -> DefinitionRef { Ref(Hash(<<41:256>>)) }
pub fn builtin_fst() -> DefinitionRef { Ref(Hash(<<42:256>>)) }
pub fn builtin_snd() -> DefinitionRef { Ref(Hash(<<43:256>>)) }
pub fn builtin_left() -> DefinitionRef { Ref(Hash(<<44:256>>)) }
pub fn builtin_right() -> DefinitionRef { Ref(Hash(<<45:256>>)) }
pub fn builtin_dict_new() -> DefinitionRef { Ref(Hash(<<46:256>>)) }
pub fn builtin_dict_get() -> DefinitionRef { Ref(Hash(<<47:256>>)) }
pub fn builtin_dict_set() -> DefinitionRef { Ref(Hash(<<48:256>>)) }
pub fn builtin_set_new() -> DefinitionRef { Ref(Hash(<<49:256>>)) }
pub fn builtin_set_insert() -> DefinitionRef { Ref(Hash(<<50:256>>)) }
