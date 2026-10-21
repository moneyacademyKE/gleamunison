# Architectural Learnings — Roadmap

## 1. Erlang Process Dictionary as LRU File Descriptor Cache
Using the process dictionary with a key like `{gleamunison_open_dets, Dir}` allows a lightweight, zero-dependency LRU file descriptor manager. This avoids complex global state management (such as GenServers) and keeps the code highly cohesive and localized to the calling process.

## 2. Erlang Soft Purge Lifecycle
`code:soft_purge/1` only purges the `old` version of a module, not the current active version. To test soft-purging, we must first delete the module using `code:delete/1` to mark it as `old`. If a process is still running code inside the module, `soft_purge` returns `false` (meaning it's in-use), allowing the loader to defer purging to a retry queue rather than crashing.

## 3. String-as-List for Loop Iterations
Using Erlang character lists like `"0123456789abcdef"` simplifies iterating through hex prefixes in Erlang. Each character is treated as an integer prefix, avoiding verbose array or binary matching structures.

## 4. O(1) Trusted Stack Tagging
Recursive validation of the algebraic handler stack during every push/pop operation is an $O(N)$ CPU bottleneck. Wrapping the verified handler list in a `{trusted_stack, List}` tuple allows the runtime to perform $O(1)$ stack validation, only validating the shape when a raw/external list is pushed.

## 5. Local Range Generator to Bypass Stdlib Discrepancies
Standard library modules like `gleam/list` and `gleam/iterator` vary in their API for range generation across different package versions. Defining a local tail-recursive `range/2` function keeps test suites highly self-contained and compile-safe.
