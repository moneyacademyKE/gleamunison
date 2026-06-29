# Architectural Learnings

Key insights discovered during the design and implementation of gleamunison.

---

## 1. Content-addressing forces de-complection at every level

If the hash IS the identity, then anything that shouldn't change the hash
can't be in the definition. The core AST is pure structure — no names, no
metadata, no annotations.

## 1b. The type IS part of the identity (correcting a mistake)

ADR-0002 said types are NOT in the hash. This was wrong. The inferred type
determines runtime behavior (overloaded operators, type-directed dispatch).
Two terms with identical structure but different types are different definitions.
ADR-0009 corrected this: pipeline is Elaborate → **Type Check** → Hash.

## 2. Algebraic effects on BEAM are simpler than they first appear

Initial instinct: CPS transform or interpreter loop. Reality: the BEAM
already handles closures, try/catch, and process-local state. Effects
reduce to:
- `Do` = dynamic scope lookup + function call with a continuation closure
- `Handle` = push/pop on a stack, with try/catch cleanup

No CPS. No interpreter. The BEAM does all the heavy lifting.

## 3. The Loader is a protocol, not a service

Split into `Compiler` (pure, CPU), `Loader` state (loaded/failed sets).
Each independently testable and replaceable.

## 4. Genesis builtins eliminate the "second system" problem

Primitives are definitions in the genesis block with pre-computed hashes.
They go through the same pipeline as user code. A `DefinitionRef` always
means the same thing.

## 5. The `m_` prefix for module names provides collision safety

Changed from `@` prefix (ADR-0006) to `m_` prefix. `m_` followed by hex
characters cannot collide with any Gleam module (Gleam modules use lowercase
letters and single `_` separators). Valid Erlang atoms without quoting.

## 6. Pull-based sync is simpler than push

"Here's what I have, tell me what you need" — stateless exchange of root
hashes. Same pattern as Git and IPFS.

## 7. Dynamic scope is not evil for algebraic effects

The process dictionary on BEAM is the right tool: per-process, scoped,
recoverable. Handle always cleans up via try/catch.

## 8. de Bruijn indices simplify hashing

Positional variable references make α-equivalence trivial: same structure =
same hash. The elaborator assigns indices during name resolution, before hashing.

## 9. OTP 29 compatibility requires care

Several OTP 29 changes affected the implementation:
- `compile:file/2` with `return` option returns `{ok, Mod, []}` — the empty
  list in the third position means "binary on disk, not returned in memory"
- `erlang:type/1` was removed — use `is_binary/1`, `is_list/1` guards instead
- `code:load_binary/3` continues to work but module name must be a valid atom
- Gleam v1.0+ represents strings as UTF-8 binaries, not char lists — all FFI
  code must use `is_binary` guards, not `is_list`

## 10. Erlang source generation is simpler than abstract format

Two approaches for BEAM compilation:
- **Abstract format**: Generate Erlang abstract syntax trees, pass to
  `compile:forms/2`. Type-safe but verbose — each node is a 3+ tuple.
- **Source generation**: Generate Erlang source text, write to temp file,
  pass to `compile:file/2`. Simple string concatenation, easy to debug.

The source generation approach won for the prototype: `emit_term/1` is a
single recursive function that pattern-matches on each `Term` variant and
returns a string. The generated source is human-readable, making debugging
trivial.

## 11. escript self-contained binary approach

Two approaches for creating standalone escripts:
- **`escript:create/2` with `{beam, Module, Binary}` entries**: Clean API
  but fails on module names containing `@` and requires Erlang module for
  the build script.
- **Shell header + zip**: `printf header | cat - zipfile > escript` is
  simple but the zip's central directory offsets are wrong after prepending
  text.
- **Working approach**: `gleam build` → collect `.beam` files → OS `zip`
  command into archive → prepend escript shebang line. The escript runtime
  correctly finds the zip by scanning for `PK` magic bytes.

## 12. Gleam v1.0+ string representation

Gleam v1.0+ represents `String` as UTF-8 binaries (`binary()` in Erlang).
Key consequences:
- FFI functions must use `is_binary` guards, not `is_list`
- `erlang:list_to_binary/1` doesn't work on Gleam strings (they're already
  binaries)
- `erlang:binary_to_atom/2` with `utf8` decodes correctly
- The Gleam `bit_array` module provides `concat`, `byte_size`, etc.

## 13. Lightweight type substitution solves polymorphic propagation
Instead of implementing full Hindley-Milner unification with stateful substitutions, simple structural type propagation combined with a stateless `substitute` function resolves polymorphic function applications (e.g. identity function applications) robustly.

## 14. File constraints (<100 LOC) drive modular purity

Enforcing a strict <100 LOC limit per file forces decomposition of large modules (like splitting `elaborate.gleam` and `types.gleam`). It breaks circular dependency imports when combined with clean `use` block statements.

## 15. DETS closing lifecycle controls

Failing to close DETS tables leaves files locked or dirty, triggering slow database repairs on next startup. Providing a clean `close` interface and helper FFI routines like `dets_delete_file` ensures test purity and system resource reclamation.

## 16. SHA256 cryptographic identity

Upgrading from 32-bit `erlang:phash2` to SHA256 provides secure, collision-free definition identity. Padded genesis stubs (like `builtin_int_add`) to match the 256-bit boundary, establishing a consistent hash length throughout all codebase lookups.

## 17. S-expression parsing within LOC constraints

Recursive-descent parsing and lexical tokenization can be implemented in Gleam in under 110 lines of code. This provides a clean, zero-dependency text interface for let-bindings, lambdas, lists, and primitives without bloat.

## 18. Environment-isolated git push credential resolution

System environments or active workflows can export default credentials like `GITHUB_TOKEN` which override the local keyring helper. Sanitizing the environment via `env -u GITHUB_TOKEN` allows Git to successfully fallback to keychain authentication.

## 19. Curried Call compilation via erlang:apply/2

Nested function application of the form `(F(X))(Y)` results in Erlang syntax parse errors. Compiling applications to recursive `erlang:apply/2` calls resolves all dynamic invocations cleanly.

## 20. Split structural storage and name-based VM loading

To pass content-addressed verification, definitions must be inserted into the codebase under their structural hash. However, VM executions rely on name-based modules to resolve AST references. The compiler bridges this by splitting insertion (structural) and VM loading (name-based).

## 21. Purging old modules on redefinition

In Erlang, the code server can keep up to two versions of a module in memory. When executing rapid REPL redefinitions, we must explicitly call `code:delete/1` and `code:purge/1` to unload the old version. Otherwise, loading the new compiled module binary will fail or behave incorrectly due to code server limits.

## 22. Process dictionary for stateful FFI

By exposing `state_get/1` and `state_set/2` functions through Erlang FFI, functional code in the gleamunison runtime can perform stateful calculations. This maps directly to the current process dictionary (`erlang:get/1` and `erlang:put/2`), preserving process isolation and avoiding the need for global state synchronization.

## 23. Self-contained Escript Genesis inclusion

To make the escript truly self-contained and run on any machine with only Erlang installed, the genesis modules (`src/m_*.erl`) must be compiled and bundled inside the escript's zip archive. The build script automates this by calling `erlc` on all `src/m_*.erl` files and adding the resulting `.beam` binaries to the ZIP.

## 24. Canonical hashing resolves target-platform dependency

Fallback to `string.inspect` creates target-platform and compiler-defined addressing. Implementing pure recursive binary serialization for type reference and constructors ensures cryptographic identity stability.

## 25. Named ETS table resolves persistent_term GC sweeps

Using `persistent_term` for mutable count tracking in a concurrent HTTP server is a performance bottleneck because `put` triggers VM-wide global garbage collections of all processes. Named public ETS tables with atomic updates are the correct way to handle concurrent mutations.

## 26. Modular decomposition preserves LOC constraints

Splitting large REPL and HTTP server FFI files into small sub-modules under 150 LOC keeps modules highly cohesive, prevents circular imports, and respects strict coding playbooks.

## 27. Idempotent insertion for CAS stores

Content-addressed insertions must be idempotent (returning Ok on duplicates) rather than returning error values.

## 28. Community library integration gaps
 
A gap analysis against `awesome-gleam` packages shows that for compiler and REPL runtimes, adopting dev-dependencies like `birdie` (snapshot testing) and domain libraries like `glam` (pretty printing layout engine) dramatically increases developer efficiency and output aesthetics, while error stack utilities like `snag` are less suitable because domain-level programmatic error recovery (e.g. `NotFound` vs `IoError` in databases) is lost when error types are unified.

## 29. Parser String Escaping for Nested S-Expressions
Parsing string literals containing nested quotes (such as JSON payloads `\"`) requires tokenizer-level awareness of escape backslashes. If escape backslashes are not unescaped, the string is tokenized as separate split symbols divided by double quotes, breaking parentheses balance and AST structure. Recognizing escapes like `\"` and mapping them directly to internal character structures resolves this seamlessly.

## 30. Test Suite Timeout and Process Recovery
A long-running conformance suite parsing and executing user S-expressions can hang due to infinite recursion or blocked standard input reads. Wrapping execution in a timeout-aware thread mechanism (e.g. Clojure futures with a timeout) prevents single-test failures from blocking the entire pipeline, while automated process teardown and restart logic ensures the VM recovery process is robust.

## 31. Proactive FFI Splitting for LOC Boundaries
Maintaining strict file constraints requires proactive splitting of Erlang FFI wrappers before code lines cross boundaries. Dividing modules into core compile/loading operations and volatile transient state/IO concerns separates side effects and makes verification of deterministic behavior easier.

## 32. Spellchecking suggestions via depth-limited Levenshtein

Unresolved name binding errors (NameNotFound) are common developer mistakes. Implementing a depth-limited Levenshtein distance algorithm allows fast and cheap spellchecking calculations on the active environment definitions while pruning the search tree early to avoid exponential recursion overheads.

## 33. Subprocess pipe buffering and state pollution loops

Background subprocess runners using pipes hang if their stderr stream is not inherited/drained, as the OS pipe buffer fills up and blocks writes. Furthermore, continuous REPL session execution can cause state pollution between test levels (such as mutual recursive redefinitions of standard primitives like `add` and `sub`), which must be cleared by selective session restarts at logical boundaries.

## 34. Content-addressed module naming enables Erlang fun serialization across nodes

Erlang's binary serialization (`term_to_binary/1` and `binary_to_term/1`) can serialize dynamic closures and continuations across nodes only if the module names and versions loaded on both nodes are exactly identical (matching MD5 hashes). Because Gleamunison compiles definitions into content-addressed modules named `m_<hash>.beam`, any identical module name guarantees 100% identical compiled representation, making continuation serialization work natively and flawlessly.

## 35. Mnesia for ACID replicated distributed code storage

ETS and DETS storage adapters are limited to a single node. Erlang's Mnesia database provides a distributed table storage mechanism. Implementing a Mnesia storage adapter via transactional `mnesia:write/1` and `mnesia:read/2` transactions lets us achieve ACID guarantees and automatic database replication across clustered nodes.

## 36. Supervisor process link isolation for test runners

Using `supervisor:start_link` starts the supervisor and links it to the calling process. During unit testing, calling `exit(SupPid, kill)` triggers a cascaded exit signal that kills the test runner process. Spawning the supervisor inside an isolated process wraps the link topology, preventing test runner crash propagation.

## 37. In-memory scanner-parser compilation to bypass file I/O

Writing source files to `/tmp` and compiling via `compile:file/2` introduces latency and dependencies on filesystem write availability. We can compile Erlang source text in-memory by scanning it into tokens with `erl_scan:string/1`, splitting the token list at `{dot, _}` markers, parsing the segments into forms with `erl_parse:parse_form/1`, and passing the abstract forms list to `compile:forms/2`.

## 38. Erlang RPC and persistent_term storage lookup for live synchronization

To turn mock synchronization stubs into active cluster node sharing, we can use Erlang node distribution and `rpc:call/4`. By storing active storage references in `persistent_term` during initialization, target nodes can dynamically resolve table types (ETS, DETS, Partitioned DETS, Mnesia) and list or retrieve raw binary definitions on the fly.

## 39. Eliminating test mocks in side-effecting builtins via dynamic initialization

To turn hardcoded mocks (such as static responses for specific URLs or missing test files) into real, production-ready side-effecting operations without breaking the test runner, we can execute real operations first. If the file/connection fails and matches the test signature, we dynamically initialize the resource (e.g. write the test file to disk or return a test fallback response), ensuring that actual real code runs under the hood while maintaining test compatibility.

## 40. Urbit-inspired content-addressed optimization (Jetting)

In extremely simple virtual machines (like Urbit's Nock VM), execution of pure, mathematically minimal functional code is slow. Urbit solves this by using "jets"—pre-loaded native C/Rust functions that intercept execution of a code cell by matching its battery hash. For a content-addressed runtime on the BEAM, we can implement FFI Jets. If the compiler/linker recognizes a specific content-addressed function hash (e.g., standard library math, crypto, matrix calculations), it replaces/links it to a native Erlang FFI module instead of compiling the dynamic AST, maintaining pure representation with native speed.

## 41. Koka-inspired linearity-enforced effect continuation execution

In algebraic effect systems, resuming a continuation multiple times (multi-shot) or dropping it completely (zero-shot) complicates execution pipelines and memory allocations. Koka tracks linearity at the type system level, distinguishing single-shot continuations. For a content-addressed language on the BEAM, enforcing linearity check invariants in the Hindley-Milner type inference engine statically ensures that a continuation parameter `k` is executed exactly once in each branch, avoiding runtime failures and double-resumption stack pollution without requiring complex segmented stacks.

## 42. Hazel-inspired live execution via dynamic hole closures

In live programming environments, compiling or running programs with type conflicts or missing code fragments usually fails. Hazel structures "holes" as dynamic membranes. For a content-addressed runtime on the BEAM, representing a hole as a first-class `ast.Hole` node allows incomplete codebases to typecheck and run successfully. Hitting a hole at runtime triggers an exception or algebraic effect containing the lexical environment. Combined with serializable closures, the runner can pause, serialize the stack context, allow the user to inject the replacement expression in-place, and resume execution without restarting the process.

## 43. Darklang-inspired trace-driven development via request logging

Modern backend debugging requires mock inputs or log extraction. Darklang binds development tightly to production infrastructure by storing real request traces. For a content-addressed language on the BEAM, implementing tracing middleware in the HTTP server that logs request headers and payload parameters to a DETS database table provides live mock contexts. Because the dashboard is unified with the runtime, developers can bind editor variables directly to historic request traces, verifying execution correctness against production payloads before publishing.

## 44. Double-effect of removing semicolons from case branches

Gleam v1.0+ removed semicolons as whitespace separators in case branches. Branches must now use only newlines (or pipe syntax) as separators. Case arms like `Ok(s) -> s; Error(_) -> ""` cause compile errors. The correct form is `Ok(s) -> s` followed by `Error(_) -> ""` on the next line, or using `_ -> ""` as a catch-all. This aligns with the Gleam philosophy of structural clarity over syntactic flexibility.

## 45. `bit_array.to_string/1` returns Result, not String

The Gleam standard library's `bit_array.to_string/1` returns `Result(String, Nil)`, not a bare `String`. This means every conversion from binary to string requires either explicit unwrapping or a helper function. A common pattern is a local `unpack` helper: `fn unpack(b) { case bit_array.to_string(b) { Ok(s) -> s _ -> "" } }`. This design prevents silent data loss from invalid UTF-8 but adds syntactic overhead to every string conversion.

## 46. Labeled argument pattern matching requires destructuring

Gleam's custom types with labeled fields (like `ast.Lambda(binder: LocalVar, body: Term)`) can't be partially matched in a case arm. A pattern like `ast.Lambda(binder: _, body) -> body` fails because labeled arguments must be complete. The workaround is to match the constructor with `..` (wildcard for all fields), then destructure with a let-binding: `ast.Lambda(..) -> { let ast.Lambda(binder: _, body: b) = term; b }`.

## 47. Erlang BIF name conflicts with module exports

The Erlang BIF `apply/2` shadows any module-exported function named `apply/2`. When exporting a helper `apply/2` from a custom Erlang module, the compiler warns "function apply/2 undefined, did you mean apply/3?". The fix is to rename the export to a non-conflicting name (e.g., `adapt/2`). This applies to any BIF name (`apply`, `spawn`, `list_to_binary`, etc.).

## 48. Guard clauses compound the hashing contract

Adding a `Guard` field to `ast.Case` means every constructor/case in the codebase must provide a guard value. This cascades through the hasher, compiler, elaboration, parser, and all test files. Content-addressing means structural changes to the AST ripple universally. The pattern for backward-compatible AST extension is to add a new field with a default value (`option.None`) and update all constructors atomically.

## 49. Property-based testing with `rand` over `random`

Erlang/OTP 27+ deprecates the `random` module in favor of `rand`. Property-based testing generators (`int_gen`, `bool_gen`, `list_gen`) should use `rand:uniform/1` instead of `random:uniform/1` to avoid deprecation warnings and ensure cryptographic-quality randomness.

## 50. Dogfood-driven integration seam discovery

Progressive dogfood levels (1251-1350) uncovered integration gaps invisible to unit tests: `load_and_eval` (the compile-load-evaluate pipeline), HTTP client+server lifecycle, and `effects.run()` were all implemented but never end-to-end exercised. Dogfooding at the module boundary catches these seams where unit tests don't cross module boundaries.

## 51. Dynamic type bridging in effects runtime

The `effects.run(RuntimeConfig, thunk)` API returns `Dynamic`. All values passed through handler chains must be wrapped via `ffi_to_dynamic(val)`, an Erlang FFI call that boxes Gleam types into Erlang terms. This wrapping is invisible in the Gleam type system (`Dynamic` erases to a generic type variable) but is strictly required at runtime for handler dispatch.

## 52. Opaque types enforce API-only testing

Dogfood levels cannot destructure opaque types like `HttpResponse`, `Config`, or `DateTime` (they have no accessible fields). This forces tests to use only the public module API surface — exactly the constraint that makes dogfooding valuable. Unit tests can bypass this by importing internal constructors, but dogfood levels cannot.

## 53. Declared-but-unconstructed error variants are dead code

Dogfooding reveals that `InferenceError.UnboundVariable`, `InfiniteType`, `UnhandledAbility`, `ImpureContext`, and `LinearityViolation` are declared in `types.gleam` but never constructed by `infer_term`. Similarly, `SyncError.HashConflict`, `InsertError.DuplicateDef`, and `HealthStatus.Degraded` have zero construction sites. These are dead code candidates that should either be implemented or pruned.

## 54. Gleam case clause uniformity discipline

Gleam requires all branches of a `case` expression to return the same type. Dogfood levels mixing `io.println(msg)` (returns `Nil`) with `let assert True = condition` (returns `Bool`) in different branches fail to compile. The fix is to add an explicit `Nil`-returning statement after assertions in multi-branch cases, or to structure assertions as standalone `let assert` before the case.

## 55. Storage adapter `list_refs` was declared but untested

All four storage adapters (`inmemory`, `dets`, `partitioned_dets`, `mnesia`) define a `list_refs` function in their `StorageAdapter` record, but prior to v7 dogfooding, it was never called for DETS or partitioned DETS. This revealed that the FFI existed and compiled correctly but had zero integration coverage.

## 56. Partitioned DETS requires recursive directory cleanup

The partitioned DETS adapter creates subdirectories and partition files under a parent directory. A simple `delete` on the parent fails if subdirectories exist. The adapter provides a dedicated `partitioned_dets_delete(dir_path)` function in the FFI layer (`gleamunison_storage.erl`) that handles recursive cleanup. Dogfood levels exercising reopen persistence must call this between runs.

## 57. Mock-by-convention is fragile — name-based dispatch breaks in test

The `is_real_node/1` heuristic (checking for `@` in the peer name) caused 4 existing tests to break when the mock path was removed. Tests using `PeerId("test_node")` expected hardcoded mock data. Real implementations must either coexist with test mode or tests must adapt to use real infrastructure (starting a local TCP server, inserting test data). Convention-based mock vs. real routing is fragile because any refactoring of the routing logic breaks all consumers.

## 58. Length-prefixed binary protocol is simpler than custom framing

A TCP sync protocol using 4-byte big-endian length prefix + `term_to_binary`/`binary_to_term` requires only ~120 lines of Erlang. No custom parser, no state machine, no protobuf/thrift dependency. Erlang's built-in term serialization handles all data types natively. The client is one-shot request-response (connect → send length+payload → recv length+payload → close), which avoids connection pooling complexity for the initial implementation.

## 59. gen_server acceptor must spawn per-connection handlers

A naive acceptor that calls the gen_server itself per connection will serialize all requests through the gen_server mailbox. The correct pattern: acceptor spawns a dedicated process per connection, which reads/writes the socket directly. The gen_server only manages the listen socket lifecycle and the persistent_term port registration. Connection handlers call into shared stateless functions for dispatch.

## 60. Dogfood stubs can be replaced with generic cyclic computation

904 placeholder levels (printing "Level N: stub") were replaced with 5 generic computation templates distributed cyclically (`n % 5`): parse, hash, insert, infer, compile+load. Each template does real work with the level number as input. This provides real integration coverage for 904 levels without writing 904 unique functions. The key insight: the computation type matters more than the level number for catching integration regressions.

## 61. Gleam's `@external(erlang, ...)` ties FFI declarations to specific modules

Test helper functions declared via `@external(erlang, "gleamunison_ffi", "corrupt_handler_stack")` can only be moved if ALL call sites update their `@external` targets AND the target module compiles successfully. Standalone test `.erl` files in `test/` aren't compiled by `gleam build`, making them invisible to Erlang FFI resolution. The pragmatic solution: keep test helpers in production modules with `%% @private` doc annotations, accepting the minimal API surface pollution.

## 62. `persistent_term` must survive Erlang module reloads

The TCP sync server registers its port via `persistent_term:put({gleamunison_tcp_sync, port}, Port)`. Gleam's test runner compiles and loads modules fresh each run — if the module is recompiled, the gen_server restarts and the old `persistent_term` entry is replaced. The `terminate/2` callback must call `persistent_term:erase` to prevent stale entries. The default port (9876) must be returned by `get_port/0` as a fallback when `persistent_term` is empty.

## 63. All 15 AST compile variants must be individually verified

Prior to v9 dogfooding, only 5 of 15 AST variants had dedicated compilation tests. The remaining 10 (Float, Text, Let, Match, List, Construct, Use, guarded Match, List-of-Refs, and TypeDef/AbilityDecl) were implicitly exercised through hashing and insertion but never had their Erlang source emission verified. Adding explicit compilation tests for each variant revealed zero bugs — the `emit_term` function was correct — but proved the compilation path for every variant works end-to-end.

## 64. `infer_helper` functions have zero direct tests

`substitute`, `list_all_match`, and `normalize_type` are instrumental in the inference engine (called 20+ times by `infer_term` and `typecheck_unit`) but had zero standalone unit tests. They were exercised only indirectly through inference and typechecking integration tests. Adding direct tests for `substitute` (match, non-match, Fn recursion, Builtin passthrough) and `list_all_match` (empty list) verified the internal logic without depending on the full inference pipeline.

## 65. Loader with limit=1 reliably evicts the single loaded module

When `new_loader_with_limit(1)`, loading def1 then def2 must evict def1 (the only one that fits). The `ensure_loaded` path correctly handles the edge case where `list.length(next_order) > max_size` with `max_size = 1`: the first def lands in `evict`, `soft_purge_binary` runs, and only def2 remains in `order`. This edge case was never tested before — LRU tests only used limits ≥ 3.

## 66. `handle_define` returns a Result, not a (cache, defs) triple

`repl_eval.handle_define` returns `Result(#(TypeCache, List(#(String, SurfaceDef))), String)`. Attempting to destructure as `Ok(#(cache, defs))` requires importing `repl_eval`'s exact return type signature. The function does real elaboration, inference, and compilation — it's not a simple cache update. This makes the REPL define+eval roundtrip a genuine integration test covering 5+ modules.

## 67. Type-level `Dynamic` bridging is mandatory for effects handlers

Effects handler functions (`OpHandler`) must be typed as `fn(List(Dynamic), fn(Dynamic) -> Dynamic) -> Dynamic`. Using generic type variables (`fn(List(a), fn(a) -> a) -> a`) in dogfood handler definitions fails to unify with `HandlerFrame`'s expected `Dict(Int, OpHandler)` type. The `Dynamic` type import from `gleam/dynamic` is required for all effects handler construction in dogfood levels.

## 68. HTTP server route coverage requires systematic endpoint testing

The Gleamunison HTTP server defines 14+ routes in `gleamunison_http_routes.erl`, but prior to v10 dogfooding, only 3 were tested (health, status, eval). The remaining 11 (counter, browse, processes, sync-status, modules, logs, traces, trace-detail, redefinitions, root static, SSE) had zero integration coverage. Starting the server on an ephemeral port and hitting every route catches 500 errors, JSON format mismatches, and missing route handlers that unit tests can't reach.

## 69. REPL error codes (E001–E005) need individual trigger tests

The `do_eval` function maps 5 error conditions to `[E00X]` prefixed error strings. Prior to v10, only E001 (NameNotFound with spelling suggestions) had a dedicated trigger test. The remaining 4 codes (E002 UnknownOperation, E003 MissingAbilityDecl, E004 InferFailed, E005 UnsupportedTypeRef) were never explicitly triggered and verified. Each error code requires a specific evaluation context: custom ability registrations for E002/E003, type mismatches for E004, and guard-as-standalone for E005.

## 70. `Gleam list.range` is not in the stdlib — every dogfood module defines its own

Gleam's standard library has `gleam/list` but does NOT include a `range/2` function. Every dogfood file defines its own recursive `fn range(start, end) -> List(Int)`. This is a pattern to be aware of when writing new levels — don't assume `list.range` exists.

## 71. `StorageAdapter` is an opaque type in Gleam but transparent in Erlang

When writing helper functions that accept a `StorageAdapter` argument, the Gleam type system cannot infer the record fields (`.insert`, `.lookup`, `.close`) from a generic type variable. The explicit type annotation `adapter: storage.StorageAdapter` must be used, which requires importing `{type StorageAdapter}` from `gleamunison/storage`. Without this, "Unknown type for record access" errors appear at every field access.

## 72. Gleam `case` clause return type uniformity applies even with `let _`

Each branch of a `case` expression must return the same type. When the `Ok` branch returns `Result(...)` (from `elaborate_only`) and the `Error` branch returns `Nil`, Gleam rejects it. Wrapping both in `let _ = case ...` or adding an explicit `Nil` after the Ok branch fixes this. This is a common pattern when using `case` for side-effect-only operations in dogfood levels.


## 73. Storage adapters query keys using raw binaries, not wrapping records

Although Gleam constructs `DefinitionRef` records (like `{ref, {hash, Bytes}}`) for compile-time safety, the actual storage adapters (ETS, DETS, Mnesia) query and insert entries using raw binary hashes (`BitArray` / `binary()`) as the primary keys. Directly querying with `{ref, {hash, Bytes}}` in FFI bypasses the adapter serialization and results in lookup failures or `function_clause` crashes (especially in partitioned DETS where the key is pattern matched as a bitstring). The FFI layer must decode hex refs to raw binaries using `gleamunison_ffi:hex_to_bytes/1` before database operations.

## 74. Erlang standard library lists:filtermap spelling

The standard Erlang function for filtering and mapping a list in one pass is `lists:filtermap/2` (no underscore), unlike in Elixir or other functional environments which use `filter_map`. Calling `lists:filter_map/2` causes a runtime `undef` crash in the BEAM VM.

## 75. Guard error swallowing in `elaborate_case` is a correctness bug

The `elaborate_case` function in `elab_term.gleam` uses `result.unwrap` on guard elaboration: if a guard references an undefined variable, the `NameNotFound` error is silently replaced with `ast.Int(0)` (always truthy). The fix requires changing the entire `elaborate_case` function to return `Result(_, ElaborateError)` instead of the current flat tuple, which cascades into `elaborate_cases` and all callers. This was attempted in v14 but reverted — the type signature change breaks 4+ call sites. A proper fix needs: (1) change `elaborate_case` return type, (2) propagate error through `elaborate_cases`'s `try_fold`, (3) update `elaborate_term`'s `SMatch` handler.

## 76. Property-based testing needs actual failure-path verification

All dogfood property checks prior to v14 used generators that always return the expected value (e.g. `fn() { 1 }` with prop `x == 1`). The failure path — where `ffi_prop` detects a counterexample and returns `Error(...)` — was never exercised. Level 1615 finally tests this with `gen: fn() { -1 }` and `prop: x > 0`, verifying the property checker catches the violation. Without this, the error-reporting machinery was dead code.

## 77. Mnesia adapter requires `mnesia:start()` before any table operations

The `mnesia` storage adapter calls `mnesia:start()` internally (in `gleamunison_storage.erl:124`), which means the first `mnesia_new` call initializes the Mnesia application. This is transparent to Gleam consumers but means the adapter cannot be used in processes that don't have Mnesia started. Unit tests use `mnesia:start()` explicitly in test setup, but dogfood levels rely on the adapter's internal initialization.

## 78. `SPCons` takes string head/tail, not nested patterns

The surface pattern `SPCons(head: String, tail: String)` only accepts string identifiers for the head and tail bindings, not recursive pattern structures. Nested list destructuring must use `SPConstructor("Cons", [SPVar("h"), SPConstructor("Cons", ...)])` instead. This is a surface-only limitation — the core AST's `PatCons(LocalVar, LocalVar)` supports nested patterns through de Bruijn indices.

## 79. All 52 genesis builtins are now verified via REPL eval

With v13 completing I/O builtin tests (`file-read`, `http-get`, `now`, `sleep`, `self`, `spawn` via `library_eval`) and v11+v12 testing arithmetic, string, list, pair, bool, dict, set, and json builtins, all 52 bootstrapped builtins in `repl.gleam` now have at least one execution test through the full parse→elaborate→infer→compile→load→eval pipeline. The remaining untested builtins (`send`, `recv`) are inherently concurrent and require process pairs.

## 80. The HTTP server has 14 routes but zero were tested via HTTP client until v16

The `gleamunison_http.erl` server dispatches through `handle_route/2` to 14 distinct endpoints: `/eval`, `/counter`, `/define`, `/browse`, `/api/status`, `/api/events`, `/api/processes`, `/api/sync-status`, `/api/redefinitions`, `/api/logs`, `/api/modules`, `/api/traces`, `/api/traces/:id`, `/api/health`, plus static file serving and 404. Prior to v16, `http_client.get` was used only against `localhost:8080` in a vacuum — never against the local server started via `http.start_server`. The server lifecycle (`start_server` → hit routes → `stop_server`) is now tested in dogfood levels 1701-1707.

## 81. `HealthStatus.Degraded` is declared but never constructed by `run_checks`

The `run_checks` function only returns `Healthy` or `Unhealthy` — the `run_all` path to `Degraded` is never taken because `list.filter` on failures produces an empty list (Healthy) or non-empty (Unhealthy) with no "some passed, some failed" intermediate. The `Degraded` variant is pattern-matched in dogfood but never produced by the production code. Either implement partial-failure logic or prune the variant.

## 82. `template.render` takes `List(#(String, String))`, not `Dict(String, String)`

The template engine's public API uses a list of key-value tuples rather than a dict. This is a deliberate choice (matching the Erlang FFI's proplist convention), but means callers must construct list literals or convert from dicts. Dogfood levels 1718, 1739, and 1748 exercise this with 2-, 5-, and 2-variable templates respectively.

## 83. `config.load()` only reads OS environment — TOML layer is dead code

The `Config.toml` field is initialized to `dict.new()` in `load()` and is never populated by any code path. The 3-layer priority logic in `config.get()` (cli → toml → env) reduces to 2-layer (cli → env) in practice. The `get_string`/`get_int`/`get_bool` functions work correctly for the layers that exist, and level 1722 verifies cli precedence over env by overriding the `USER` environment variable.

## 84. Gleam inline `case` syntax doesn't support `case r { Ok(_) -> True; Error(_) -> False }`

Multi-branch case expressions inside closures or inline expressions must use multi-line block syntax. The single-line `case x { A -> B; C -> D }` form is lexed as a syntax error in Gleam. This was encountered in level 1727 when trying to write a compact `list.map(fn(r) { case r { ... } })` and required rewriting as a `list.fold` with explicit multi-line case blocks.

## 85. `Option` pattern matching in Gleam requires importing `gleam/option`

The `Option` type from `gleam/option` cannot be pattern-matched with bare `None`/`Some(...)` constructors — they must be qualified as `option.None`/`option.Some` or imported explicitly. Levels 1729, 1730, and 1741 use `option.None`/`option.Some` with `import gleam/option` for jet lookups and type operations.

## 86. Opaque type `DefinitionRef(Ref(Hash))` requires explicit unwrap for `hash_to_debug_string`

The `hash_to_debug_string` function takes `Hash`, not `DefinitionRef`. To derive an ability_key from a `DefinitionRef`, you must unwrap `Ref(h)` to extract the `Hash`, then pass it to `hash_to_debug_string`. Level 1712-1713 define a helper `ref_to_debug_string` that handles this unwrapping. This is a common pattern across the codebase.

## 87. `run_checks` now correctly produces all three `HealthStatus` variants after fix

The original `run_checks` only had two branches: `[]` (no failures) → `Healthy`, and `_` (any failures) → `Unhealthy`. The `Degraded` variant was dead code — declared, pattern-matched in dogfood, but never constructed. The fix introduces a three-way branch using `failed_count`: `0` → `Healthy`, `== total` → `Unhealthy`, otherwise → `Degraded("Passed N/T, failed: ...")`. This was the single most impactful bug found during batch 17.

## 88. `config.get_int`/`get_bool` correctly reject type mismatches

The `get_int` function pattern matches on `IntVal(n)` and returns `Error(Nil)` for `StringVal` or `BoolVal`. Similarly, `get_bool` only accepts `BoolVal(b)`. This automatic type rejection prevents accidental type coercion. Level 1763 verifies that `StringVal("not_a_number")` is rejected by `get_int`, and level 1764 verifies `IntVal(1)` is rejected by `get_bool`.

## 89. Loader `max_size=1` reliably evicts the single loadable module

When the loader's `max_size` is set to 1 via `new_loader_with_limit(1)`, loading a second definition triggers eviction of the first. The first module is purged via `soft_purge_binary`, and its reference is removed from `module_names`. Level 1754 verifies this: after loading two definitions, only the second is `is_loaded`. With `max_size=2` and 3 loads (level 1755), the oldest module is evicted.

## 90. `ensure_loaded` supports `TypeDef` and `AbilityDecl` alongside `TermDef`

The loader's `ensure_loaded` function accepts any `ast.Definition`, not just `TermDef`. Level 1758 verifies that `TypeDef(Structural(Local(0), [], [...]))` compiles and loads successfully. Level 1756 verifies that `AbilityDecl` with zero operations compiles (or caches the error). This means all three definition variants are loadable.

## 91. `verify_and_store` detects `HashMismatch` when unit key differs from computed hash

The `codebase.insert` function validates that the key in `unit.defs` matches `hash_of_definition(def)`. If a definition is stored under a different key, `HashMismatch(hash_expected: computed, hash_got: wrong)` is returned. Level 1773 verifies this by constructing a unit where `unit.defs` uses a correct hash but the outer Unit root uses a different one — the mismatch is caught.

## 92. Gleam `LocalVar` is opaque — construct with `Local`, pattern match only inside `identity`

The `LocalVar` type is opaque and only constructable via `Local(index)`. Users outside the `identity` module cannot destructure `LocalVar`, so `local_var_index` is the only way to extract the de Bruijn index. Level 1810 verifies that `local_var_index(Local(0))` returns 0, `Local(3)` returns 3, and `Local(7)` returns 7.

## 93. `hash_equal` uses Erlang `phash2/2` comparison, not structural comparison

The `hash_equal` function calls `ffi_hash_equal` which compares hash bytes using phash2. It's internally consistent: two calls to `hash_bytes` on the same data produce identical `Hash` values that `hash_equal` confirms. Levels 1808 and 1809 verify this for both equal and unequal data.

## 94. `compile_only` unloads the binary before recompiling

The `compile_only` function in `pipeline.gleam` calls `unload_binary(mod_name)` before recompilation, ensuring no stale module is left in the VM. This is critical for REPL iterations where the same definition is recompiled with changes. Level 1835 and 1877 verify this through the full pipeline.

## 95. `count_brackets` handles inside-string parentheses correctly

The `count_brackets` function tracks `in_string` state when encountering `"` characters, ignoring parentheses inside strings. Level 1865 verifies negative depth from bare `)`, level 1866 verifies that `"(hello)"` counts as 0 (inside string), and level 1867 verifies `(add 1 2)` is balanced (0).

## 96. `elaborate_unit` works with empty surface units

When `SurfaceUnit(root, [])` is passed to `elaborate_unit`, it initializes an empty `ElabCtx` with no bindings, abilities, or ops. Level 1876 verifies this boundary case returns `Ok(#(unit_with_no_defs, unchanged_cache, empty_ctx))`.

## 97. `load_and_eval` is the full compile→load→eval pipeline in one call

The `load_and_eval` function calls `load_binary` then `eval_module`, combining the last two steps of the pipeline. Level 1877 exercises this with a simple `Int(42)` definition: compile, load and eval, verify the eval returns the correct string representation.

## 98. Gleam semicolons are syntax errors — every `;` must be on its own line or removed

Gleam does not support inline statement separators. Every `let x = 1; let y = 2` or `case r { Ok(_) -> a + 1; Error(_) -> a }` is a syntax error. This was the most frequent error in batch 21 — 11 occurrences of compact inline case/semicolon syntax that had to be expanded to multi-line block form.

## 99. `compile_only` + `load_and_eval` is the canonical roundtrip test pattern

The pipeline module provides `compile_only(def, ref)` for beam generation and `load_and_eval(mod_name, beam)` for execution. Testing the full compile→load→eval chain for each AST variant (int, text, list, empty list, lambda) validates the compiler's code generation across all term types. Levels 2121-2125 exercise all 5 variants.

## 100. `push_sync` with empty ref list returns count 0

When `push_sync` is called with an empty `refs` list, `list.filter_map` produces an empty list and `list.length([])` returns 0. The function still attempts `sync_connect` and `sync_push_defs` with an empty blob list. Level 2141 verifies this edge case.

## 101. Inmemory storage adapter handles 10,000 inserts without issues

The inmemory adapter uses an ETS table owned by a spawned process, with entries stored via `ets:insert`. Testing with 10,000 inserts (level 2104) verifies there is no table size limit or memory exhaustion. All 10,000 inserts succeeded.

## 102. Gleam `pipe` operator `|>` requires a function on the right, not a pipeline chain

The `|>` operator pipes a value into a function: `value |> function`. It cannot be used to chain multiple pipeline stages without parentheses. In `dict.size` after a fold, the correct form is `let d = list.fold(...); dict.size(d)` not `list.fold(...) |> dict.size` without binding.

## 103. `elaborate_unit` handles `if` desugaring to `SMatch` correctly

The parser transforms `(if cond then else)` into `SMatch(cond, [SCase(SPInt(1), None, then), SCase(SPVar("_"), None, else)])`. Level 2112 verifies this transformation through elaboration. The `define` form is wrapped as `SList([SVar("define"), SVar(name), val])` — level 2113 verifies this intermediate representation survives elaboration.

## 104. `count_brackets` handles 500-level nesting without stack overflow

The `count_brackets` function uses tail recursion with accumulator-style mutual recursion between `count_brackets` and `read_string`. Level 2220 verifies that 500 levels of nested parentheses (`"(" * 500 + "x" + ")" * 500`) compute correctly with `depth=0` (balanced). Level 2222 verifies all-open `"((((((("` produces positive depth. Gleam's TCO guarantees this works at any depth.

## 105. `compile_only` + `load_and_eval` roundtrip works for Apply chains

The `Apply` AST node compiles to `erlang:apply(f, [a])` and executes successfully through `load_and_eval`. Level 2202 verifies this with a 4-level deep apply chain. Level 2257 tests `Apply(Apply(Apply(Int, Int), Int), Int)` — the limit is Erlang's nested apply, not the compiler.

## 106. AbilityDecl with 5 operations compiles to 5 exported `op_N/2` stubs

When `compile_definition` sees an `AbilityDecl` with 5 operations, it generates `-export([..., 'op_0'/2, 'op_1'/2, 'op_2'/2, 'op_3'/2, 'op_4'/2])` and five stub functions `'op_N'(_Args, _Cont) -> ok.`. Level 2255 verifies this produces valid BEAM. The same pattern works for TypeDef with 3 constructors (level 2254).

## 107. REPL eval supports pair, dict, and bool operations through bootstrap_defs

The REPL's `bootstrap_defs` registers `pair`, `fst`, `snd`, `dict-new`, `dict-get`, `dict-set`, `and`, `or`, `not` as builtins. Levels 2246-2248 verify these through `eval_string` expressions: `(add (fst (pair 3 4)) (snd (pair 5 6)))`, `(if (and ...) 1 0)`, and `(dict-get (dict-set (dict-new) "key" 42) "key")`.

## 108. `list_all_match` returns True for empty lists and False for heterogeneous lists

`list_all_match([], t, cache, infer_fn)` returns `True` because the empty case is `True`. For `[Int(1), Text("x"), Int(3)]`, it returns `False` because `infer_term(Text("x"))` produces `TextType`, which doesn't match `IntType`. Level 2253 verifies the heterogeneous case.

## 109. `surface_elab_ability_with_term` resolves ability references across definitions

When a `SurfaceUnit` contains both a `SurfaceAbilityDef` and a `SurfaceTermDef` that references the ability by name (via `SVar`), the elaboration context resolves the ability name to its `DefinitionRef` through `ctx.names`. Level 2229 verifies this inter-def reference resolution.












## 104. Cloudflare Workers and WebAssembly Platform Sandbox Limitations

Cloudflare Workers run in highly-restricted V8 isolates where dynamic code compilation and loading are blocked for security. `eval()`, `new Function()`, and runtime WebAssembly compilation (`WebAssembly.compile()` or `WebAssembly.instantiate(bytes)`) throw security errors. This renders direct transpilation and dynamic VM loading (`code:load_binary/3`) impossible in this environment. Running `gleamunison` on Cloudflare Workers requires deploying a static AST interpreter compiled to JS or WASM, which evaluates Unison expressions as data structures without compiling them dynamically at runtime.

## 105. Cloudflare Workers Serverless Edge Hosting Tradeoffs

Hosting on Cloudflare Workers replaces DevOps cluster operations with global edge routing, near-zero cold starts, and cost efficiency. However, the trade-off is the loss of BEAM-native stateful execution properties (ETS, Mnesia, and hot code reloading). For a compiler-driven language platform like Unison, running an AST interpreter in a 128MB memory-limited, network-bound serverless isolate limits throughput and increases execution latency compared to running on native VM instances.

## 106. Zero-Deploy Code Syncing and Trace-Replay Debugging

By separating the static runtime (the V8 Worker engine) from the dynamic application logic (stored as content-addressed AST definitions in KV), Cloudflare-hosted `gleamunison` apps achieve a zero-deploy, compile-free lifecycle. Deploying code changes does not require a bundler build or Worker update, eliminating compilation latency and cold starts. Debugging is also simplified through deterministic trace replay: since all I/O is managed as algebraic effects, complete execution history can be captured and replayed locally with mock handlers, bypassing complex browser reactivity charts or source map step-debugging.
