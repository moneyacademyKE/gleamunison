//// One declaration authority for the BEAM loader family.
////
//// Four externals — source text to a binary, a BEAM binary into the code
//// server, back out again, and a call into a loaded module — were declared
//// two or three times each across loader, pipeline, elaborate, parser and
//// repl_eval, always with the identical signature. `repl_eval` even published
//// two of them, which made it a second authority for a concern it does not
//// own — and `elaborate` cannot import `repl_eval` (repl_eval imports
//// elaborate), so half the tree was forced to re-declare instead.
////
//// This module depends on nothing, so any module can use it without a cycle.

/// Compile-side view of source text: the binary form the loader wants.
@external(erlang, "gleamunison_ffi", "string_to_binary")
pub fn string_to_binary(s: String) -> BitArray

/// Put compiled BEAM bytes into the code server under `mod_name`.
@external(erlang, "gleamunison_ffi", "load_binary")
pub fn load_binary(mod_name: String, beam: BitArray) -> Result(Nil, String)

/// Take a loaded module out of the code server again.
@external(erlang, "gleamunison_ffi", "unload_binary")
pub fn unload_binary(mod_name: String) -> Result(Nil, String)

/// Call into a loaded module and read back its rendered result.
@external(erlang, "gleamunison_repl_ffi", "eval_module")
pub fn eval_module(mod_name: String) -> Result(String, String)
