# ADR-0011: m_ prefix module naming

**Status:** Accepted

**Date:** 2026-06-26

**Supersedes:** ADR-0006 (implementation practice)

## Context

ADR-0006 specified `@`-prefixed module names for collision safety. During
implementation, two issues were discovered:

1. **`compile:file/2` compatibility**: The Erlang compiler accepts
   `-module('@a1b2c3').` in source but some filesystems and tooling handle
   `@`-prefixed filenames inconsistently. The temp file `@a1b2c3.erl` is
   valid on macOS APFS but may cause issues on other filesystems.

2. **`escript:create/2` rejection**: The `escript:create/2` function returns
   `{error, {badarg, {beam, Module, Binary}}}` when `Module` is a `@`-prefixed
   atom. The `escript` module validates module names and rejects `@` as the
   first character.

## Decision

Use the `m_` prefix followed by the last 8 hex characters of the hash:

```
m_04cc725a
```

The `m_` prefix:
- Is a standard Erlang atom — no quoting needed, no special characters
- Cannot collide with any Gleam-compiled module — Gleam uses lowercase letters
  and underscores but never `m_` followed by hex digits
- Works with `escript:create/2`, `compile:file/2`, `code:load_binary/3`
- Is readable in backtraces and error messages

Module naming function:
```gleam
pub fn module_name_for(ref: DefinitionRef) -> String {
  let Ref(hash) = ref
  let full = hash_to_debug_string(hash)
  "m_" <> string.slice(full, string.length(full) - 8, 8)
}
```

Uses the last 8 hex characters (not the first 8) because `phash2` returns
a 32-bit value packed into 32 bits (4 bytes = 8 hex chars). The module name
is the entire hash string.

## Consequences

**Positive:**
- Works with all OTP module tooling (compile, load, escript)
- Readable module names in backtraces
- Simpler atom construction — `binary_to_atom("m_04cc725a", utf8)`, no quoting

**Negative:**
- Slightly weaker isolation guarantee: `m_` prefix could theoretically be
  produced by a user module named `m_something`. Mitigation: the full hash
  (8 hex chars) follows the prefix — a user would need to both use the
  `m_` prefix and match a specific hash. Effectively impossible.

**Alternatives considered:**
- `@` prefix (ADR-0006): rejected due to escript incompatibility
- Numeric prefix only: rejected — atoms starting with digits are invalid
- Full hex hash without prefix: risk of collision with Gleam-generated module
  names (Gleam uses `@` for module name hashing)
