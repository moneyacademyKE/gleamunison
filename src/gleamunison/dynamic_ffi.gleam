//// One declaration authority for the term <-> Dynamic casts.
////
//// On the BEAM a `Dynamic` *is* the term, so both directions compile to the
//// identity function in `gleamunison_ffi`. gleam_stdlib's `dynamic` module
//// only ships per-type identities (`dynamic.int`, `dynamic.string`, ...), so
//// the polymorphic pair has to be owned somewhere — here, once.
////
//// Before this module the same two externals were re-declared 18 times under
//// seven drifting names (`cast`/`uncast`/`coerce`/`text_arg`/`as_result`/
//// `as_bit_array`/`unsafe_coerce`), several of them pointing at `to_dynamic`
//// for what is really the *from* direction. One name per direction.

import gleam/dynamic.{type Dynamic}

/// Name an ordinary term as an untyped dynamic value.
@external(erlang, "gleamunison_ffi", "to_dynamic")
pub fn to_dynamic(val: a) -> Dynamic

/// Read an untyped dynamic value back as a concrete type. The cast is unchecked:
/// a wrong shape surfaces later, at the point of use, not here.
@external(erlang, "gleamunison_ffi", "from_dynamic")
pub fn from_dynamic(val: Dynamic) -> a
