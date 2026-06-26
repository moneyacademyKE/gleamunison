# ADR-0005: Loader decomposition into three services

**Status:** Accepted

**Date:** 2026-06-26

## Context

The first design had a monolithic `Loader` that fetched definitions, compiled
them to BEAM bytecode, and loaded them into the VM. Three different operations
with three different failure modes:

| Operation | Failure mode | Latency | Side effects |
|---|---|---|---|
| Fetch | Network error, missing def | ms-s (IO) | None |
| Compile | Malformed AST, unsupported term | μs-ms (CPU) | Pure computation |
| Load | Name collision, corrupt binary | μs (VM) | VM state change |

Complecting them means a network timeout during fetch prevents retrying
compilation (which had already succeeded). A compilation error prevents
admitting that the definition exists (but is broken).

## Decision

Decompose the Loader into three services, orchestrated by a thin coordinator:

```gleam
pub type Loader {
  Loader(
    store: CodebaseStore,        // fetch only
    compiler: CompilerService,   // compile only
    loader: ModuleLoader,        // load only
    loaded: Set(DefinitionRef),
    failed: Map(Ref, LoaderError),
    in_flight: Map(Ref, Promise),
  )
}
```

Each service has a single responsibility. The coordinator handles retry logic,
caching, and concurrency deduplication.

## Consequences

**Positive:**
- Each service is independently testable — mock the other two
- Each service can be independently replaced (e.g., swap `CompilerService`
  for a different compilation backend)
- Clear error boundaries: `FetchFailed`, `CompileFailed`, `LoadFailed` are
  distinct error types
- The coordinator is thin — it doesn't execute any of the work, just
  orchestrates it

**Negative:**
- More indirection: a simple load now involves three lookups (cache, store,
  loader state) and three service calls
- The coordinator must handle partial success (e.g., 5 refs requested, 3
  already loaded, 1 missing from store, 1 compiled but failed to load)

**Key invariant:** The `failed` set prevents repeated failed compilation. The
`in_flight` map coalesces concurrent requests for the same ref (via promises).
No cache stampede, no repeated failure.
