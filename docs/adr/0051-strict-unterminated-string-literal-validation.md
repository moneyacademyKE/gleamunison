# ADR-0051: Strict Unterminated String Literal Validation

## Context
In our effort to ensure syntax compliance for the `gleamunison` parser, we noticed a bug where unclosed string literals at the end of files (EOF) were silently auto-terminated and parsed as valid strings instead of raising a syntax error. 

For instance, the source text `"\"unterminated"` was parsed successfully as `SText(<<"unterminated">>)`, violating Level 1085's specification which expects a parser syntax error.

## Decision
We decided to enforce strict string literal termination checks by introducing a new token variant:
1. **UnterminatedString(String)** is added to `lexer.Token` type.
2. In `lexer.read_string`, when reaching EOF (`[]`) while still accumulating a string, we return `TokenInfo(UnterminatedString(acc), sl, sc)` instead of auto-closing.
3. In `parser.parse_sexpr` and `parser.sexpr_to_term`, we match `UnterminatedString` and raise an explicit `Error(ParseError("Unterminated string literal", line, col))`.

This non-breaking token representation maintains the downstream signature contracts of `lexer.tokenize` (returning `List(TokenInfo)`) while enabling correct error propagation in the parser.

## Consequences
- **Unclosed String Enforcement**: Unclosed string literals are now correctly identified and rejected with a syntax error, preventing malformed source execution.
- **Backwards Compatibility**: No changes to existing dogfood levels or tokenizer type signatures were required.
