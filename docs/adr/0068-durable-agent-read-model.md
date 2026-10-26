# ADR 0068: One durable agent read model with explicit scratch overlays

- **Status:** Accepted
- **Date:** 2026-10-26 (EAT)
- **Tracking:** Bankai `bk-fe15`
- **Related:** [ADR 0001](0001-content-addressed-identity.md), [ADR 0009](0009-types-in-definition-hash.md), [ADR 0065](0065-verified-cas-admission.md)

## Context

MCP booted only bootstrap surface definitions. The HTTP session independently owned another bootstrap snapshot, and `find` searched bootstrap names while printing dependency/name handles as discovery refs. Published definitions in a branch namespace and CAS were therefore invisible to the agent surfaces. HTTP `/define` was visible to later HTTP evals but not MCP.

The tempting shortcut is to wrap every stored definition as a surface `SRef(content_hash)` and re-elaborate it. That computes a new definition whose identity is a reference, not the stored content. Another shortcut is to copy scratch into CAS; that gives mutable work-in-progress a durable identity it has not earned.

## Decision

1. **A durable entry is data, not reconstructed source.** The selected branch maps names to content refs. Each entry retains the decoded AST, exact content ref, kind, branch, and stored type. Metadata exposes `ref`, `name_ref`, `origin`, and `branch` separately.
2. **Surface projection is only for elaboration.** A stored term may be projected as `SRef(content_ref)` with its stored type seeded into the cache. This projection is never hashed and never described as source. Stored graph edges come from the AST and resolve through selected-branch names.
3. **Scratch is an explicit overlay.** Bootstrap and loaded/redefined source entries are marked `bootstrap` or `scratch`. A scratch definition shadows a same-named branch entry for the session without modifying the branch pointer or CAS.
4. **One process owns scratch.** The supervised web session owns HTTP mutations and current snapshots. The MCP process is a bounded RPC gateway over those snapshots, not a second session with an immutable-at-boot copy. `/browse` and MCP serialize the same visible catalog.
5. **One node storage selection.** Agent startup reuses the active backend registered by storage, or opens the configured default through the existing store-context resolver. `GLEAMUNISON_BRANCH` selects a branch, defaulting to `main`. `find` uses this same startup path and accepts `--load` as scratch input.
6. **Stored dependencies load before evaluation.** The existing closure loader resolves selected name refs through the branch namespace before scratch expressions execute. A stored caller therefore follows the selected branch's dependency binding.

## Consequences

- MCP, HTTP, and CLI discover published code without mutating it.
- The same stored caller hash can resolve its named dependency differently on different branches, as the runtime already specifies.
- Stored metadata search covers names and kinds, not invented source bodies. Source scratch retains body-token search.
- The branch is a startup selection in this change; switching a live session's branch is not claimed.
- An entry with no elaborated/stored content ref reports JSON `null` (CLI `-`), never a name hash masquerading as content.
- Loading the selected branch may fail visibly when its CAS or dependency closure is unreadable; absence of a branch is still an empty durable namespace, not silent recovery from storage errors.

## Alternatives rejected

- **Hash the surface `SRef` projection:** rejected; it changes identity and reproduces the original name/content confusion.
- **Publish scratch implicitly:** rejected; mutable work has not passed the evidence turnstile.
- **Keep independent MCP and HTTP snapshots:** rejected; it preserves the state fork and makes visibility depend on startup order.
- **Re-elaborate stored AST into fabricated source:** rejected; needless conversion, identity drift, and incidental complexity.

**Rich Hickey check:** immutable stored entries and mutable overlays compose as data; one owner handles mutation. The rejected alternatives complect identity with presentation and durability with convenience.
