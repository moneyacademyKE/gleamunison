# ADR-0006: @-prefixed module naming

**Status:** Amended by practice — now `m_`-prefixed

**Date:** 2026-06-26

**Amendment:** During implementation, the `@` prefix was changed to `m_`
    prefix. See ADR-0011 for the decision record.

## Context

Each compiled `Definition` becomes a BEAM module. The module name must be
derived from the `DefinitionRef` hash. The naive approach is to use the
hex-encoded hash directly: `module_code_a1b2c3`.

Problem: Erlang module names are atoms. Any Erlang or Gleam source file can
produce any atom as a module name. If a user writes `-module(code_a1b2c3).`
in their code, and that hash happens to exist in the codebase, the names
collide.

## Decision

Use the `@` character as a prefix: `'@a1b2c3'`. The `@` prefix:

- Is a valid Erlang atom (with single-quote syntax: `'@a1b2c3'`)
- Cannot be produced by any Erlang or Gleam source file
  - Erlang module names are bare atoms or single-quoted atoms, but `@` at
    the start requires single-quoting
  - Gleam compiles to Erlang modules, so the same constraint applies
  - Neither language allows `@` as the first character of a bare module name

## Consequences

**Positive:**
- Isolation guarantee: user code can never accidentally collide with a
  content-addressed module name

**Negative:**
- `@`-prefixed quoted atoms (`'@abc'`) are valid Erlang but caused issues
  with `compile:file/2` on some filesystems
- Quoted atoms are mildly annoying in backtraces and error messages
- `escript:create/2` rejects `@` in module names with `{error, einval}`
