//// One admission policy before grapheme expansion or recursive parsing.
//// Limits are resource policy, not grammar; the parser still diagnoses syntax.

pub type Budget {
  Budget(bytes: Int, tokens: Int, depth: Int, forms: Int, token_bytes: Int)
}

fn defaults() -> Budget {
  Budget(
    bytes: 1_048_576,
    tokens: 100_000,
    depth: 1024,
    forms: 4096,
    token_bytes: 16_384,
  )
}

@external(erlang, "gleamunison_source_budget", "check")
fn check_bytes(
  source: String,
  bytes: Int,
  tokens: Int,
  depth: Int,
  forms: Int,
  token_bytes: Int,
) -> Result(Nil, String)

pub fn check(source: String) -> Result(Nil, String) {
  check_with(source, defaults())
}

pub fn check_with(source: String, budget: Budget) -> Result(Nil, String) {
  check_bytes(
    source,
    budget.bytes,
    budget.tokens,
    budget.depth,
    budget.forms,
    budget.token_bytes,
  )
}
