import gleamunison/identity.{type DefinitionRef, Ref}

pub fn builtin_int_add() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<1:256>>))
}

pub fn builtin_io_read_line() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<2:256>>))
}

pub fn builtin_state_get() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<3:256>>))
}

pub fn builtin_state_put() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<4:256>>))
}

pub fn builtin_process_spawn() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<5:256>>))
}

pub fn builtin_process_self() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<6:256>>))
}

pub fn builtin_process_send() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<7:256>>))
}

pub fn builtin_process_recv() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<8:256>>))
}

pub fn builtin_timer_sleep() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<9:256>>))
}

pub fn builtin_timer_now() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<10:256>>))
}

// Arithmetic (101-102)
pub fn builtin_sub() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<11:256>>))
}

pub fn builtin_mul() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<12:256>>))
}

pub fn builtin_div() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<13:256>>))
}

pub fn builtin_mod() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<14:256>>))
}

// Comparison (103)
pub fn builtin_eq() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<15:256>>))
}

pub fn builtin_lt() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<16:256>>))
}

pub fn builtin_gt() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<17:256>>))
}

// Boolean (104)
pub fn builtin_and() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<18:256>>))
}

pub fn builtin_or() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<19:256>>))
}

pub fn builtin_not() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<20:256>>))
}

// String ops (151-160)
pub fn builtin_string_concat() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<21:256>>))
}

pub fn builtin_string_length() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<22:256>>))
}

pub fn builtin_string_contains() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<23:256>>))
}

pub fn builtin_string_slice() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<24:256>>))
}

pub fn builtin_string_upcase() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<25:256>>))
}

pub fn builtin_string_downcase() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<26:256>>))
}

pub fn builtin_string_replace() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<27:256>>))
}

pub fn builtin_string_split() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<28:256>>))
}

pub fn builtin_string_trim() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<29:256>>))
}

pub fn builtin_string_to_int() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<30:256>>))
}

// List ops (161-170)
pub fn builtin_list_length() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<31:256>>))
}

pub fn builtin_list_reverse() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<32:256>>))
}

pub fn builtin_list_map() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<33:256>>))
}

pub fn builtin_list_filter() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<34:256>>))
}

pub fn builtin_list_fold() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<35:256>>))
}

pub fn builtin_list_append() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<36:256>>))
}

pub fn builtin_list_flatten() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<37:256>>))
}

pub fn builtin_list_member() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<38:256>>))
}

pub fn builtin_list_range() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<39:256>>))
}

pub fn builtin_list_sort() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<40:256>>))
}

// Data structures (171-180)
pub fn builtin_pair() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<41:256>>))
}

pub fn builtin_fst() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<42:256>>))
}

pub fn builtin_snd() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<43:256>>))
}

pub fn builtin_left() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<44:256>>))
}

pub fn builtin_right() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<45:256>>))
}

pub fn builtin_dict_new() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<46:256>>))
}

pub fn builtin_dict_get() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<47:256>>))
}

pub fn builtin_dict_set() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<48:256>>))
}

pub fn builtin_set_new() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<49:256>>))
}

pub fn builtin_set_insert() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<50:256>>))
}

pub fn builtin_json_parse() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<51:256>>))
}

pub fn builtin_http_get() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<52:256>>))
}

pub fn builtin_file_read() -> DefinitionRef {
  Ref(identity.hash_from_bytes(<<53:256>>))
}
