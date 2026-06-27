# Architectural Decision Record (ADR) 0038: Type Pretty-Printing Module

## Context

Type error messages and REPL output needed human-readable type representations. Early implementations used Gleam's `string.inspect` on type AST nodes, producing verbose, internal representations that were hard for users to parse visually.

The pretty-printing concern is orthogonal to the type system itself: it's a display/formatting concern, not a type-checking concern. It should be decomposed into its own module.

## Decision

Create `type_pretty.gleam` as a dedicated type pretty-printing module:

1. **Library integration**: Uses `glam` (community pretty-printer library, ADR-0027) for layout-aware document construction. `glam` provides `Document` types with `group`, `line`, `nest` combinators that handle line-breaking and indentation automatically.
2. **Type variable naming**: Generates human-readable names (e.g., `a`, `b`, `c`, ... `z`, `a1`, `a2`, ...) from de Bruijn indices using alphabetical cycling.
3. **Hash shortening**: Renders `DefinitionRef` hashes as 8-character hex strings (`hash_to_short_string`) for display compactness.
4. **Recursive type printing**: Prints type constructors (`Int`, `Float`, `Text`, `List(a)`, function types `a -> b`) with proper parentheses and spacing.

## Status

Accepted.

## Consequences

- Type errors render as readable strings like `Expected: Int, Found: List(Text)` instead of internal AST dumps.
- REPL output is more compact and readable.
- `glam` handles line-wrapping at terminal width automatically — no manual string-width calculations.
- Future extension points: syntax-highlighted type output, colorized terminal rendering, HTML type display for web dashboard.
- Module stays under 250 LOC by delegating layout decisions to `glam`.
