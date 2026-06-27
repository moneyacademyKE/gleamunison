# Architectural Decision Record (ADR) 0035: Lexer-Parser Separation

## Context

The original parser (`parser.gleam`) performed both tokenization (lexing) and parsing in a single module. As the surface language grew to support multi-line REPL input, escaped quotes in string literals, float literals, `;` comments, `+` operator aliases, and `'` quote reader macros, the combined lexer+parser module approached the 250 LOC limit.

Furthermore, spelling suggestions (ADR-0033) required bracket-counting logic that operated at the token level before parsing, and the tokenizer's coordinate tracking (line/column positions for diagnostics) was a distinct concern from AST construction.

## Decision

Split the parser into two modules:
1. **`lexer.gleam`**: Tokenizer producing `Token` and `TokenInfo { token, line, col }`. Handles string escape sequences (`\"`, `\\`), numeric literal recognition (Int vs Float), and symbol scanning. Returns a `List(Token)` for consumption by the parser.
2. **`parser.gleam`**: Consumes the token stream and produces the AST. Operates purely on tokens without character-level logic. Handles bracket matching, S-expression structure, `;` comment skipping, and `'` quote reader macro expansion.

## Status

Accepted.

## Consequences

- Lexer can be tested independently with snapshot tests against token sequences (see `test/parser_snapshot_test.gleam`).
- Parser is simpler: operates on tokens rather than characters, reducing state management.
- Bracket counting for multi-line REPL input uses lexer output without needing parser state.
- Token coordinate metadata (`TokenInfo`) enables precise `ParseError` diagnostics with line/column information.
- Both modules remain under the 250 LOC limit.
- Future surface syntax extensions (e.g., new token types) only require lexer changes.
