//// A single-use cancellation flag shared by caller and transport. No server,
//// registry, or background job is needed to cancel an outstanding request.

import gleam/dynamic.{type Dynamic}

/// Holds the Erlang atomics reference. The constructor is used here, so the
/// type is a real value the FFI returns into rather than a name it pretends
/// to produce; the reference never escapes the module.
pub opaque type Token {
  Token(Dynamic)
}

@external(erlang, "gleamunison_cancellation", "new")
fn ffi_new() -> Dynamic

@external(erlang, "gleamunison_cancellation", "cancel")
fn ffi_cancel(token: Dynamic) -> Nil

@external(erlang, "gleamunison_cancellation", "cancelled")
fn ffi_cancelled(token: Dynamic) -> Bool

pub fn new() -> Token {
  Token(ffi_new())
}

pub fn cancel(token: Token) -> Nil {
  let Token(inner) = token
  ffi_cancel(inner)
}

pub fn is_cancelled(token: Token) -> Bool {
  let Token(inner) = token
  ffi_cancelled(inner)
}
