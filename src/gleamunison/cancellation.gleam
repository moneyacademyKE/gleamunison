//// A single-use cancellation flag shared by caller and transport. No server,
//// registry, or background job is needed to cancel an outstanding request.

pub opaque type Token {
  Token
}

@external(erlang, "gleamunison_cancellation", "new")
pub fn new() -> Token

@external(erlang, "gleamunison_cancellation", "cancel")
pub fn cancel(token: Token) -> Nil
