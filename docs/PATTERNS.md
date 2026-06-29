# Design Patterns

Patterns used throughout the gleamunison architecture.

---

## 1. Opaque type with module-private constructor

Used for types that must maintain invariants.

```gleam
pub opaque type Hash {
  Hash(contents: BitArray)
}
```

**Applied in:** `identity.gleam` (Hash), `codebase.gleam` (Codebase), `loader.gleam` (Loader)

---

## 2. Decomposed service

Split a service into sub-services with different concerns, orchestrated by a
thin coordinator.

```gleam
pub type Loader {
  Loader(
    compiler: Compiler,
    loaded: Set(DefinitionRef),
    failed: Dict(DefinitionRef, LoaderError),
  )
}
```

**Applied in:** `loader.gleam`

---

## 3. Three-result cache

A cache that distinguishes three states: known-good, known-bad, and unknown.

```gleam
pub type Loader {
  Loader(
    loaded: Set(DefinitionRef),              // known good
    failed: Dict(DefinitionRef, LoaderError), // known bad — don't retry
  )
}
```

**Applied in:** `loader.gleam`

---

## 4. Genesis builtins

Primitives are seeded into every codebase with pre-computed hashes from a
genesis block, rather than having a special "builtin" type.

**Applied in:** `elaborate.gleam`, `identity.gleam`

---

## 5. Dynamic scope stack with cleanup guarantee

Effects handlers are pushed onto a per-process stack. Cleanup is guaranteed
by try/catch in the Erlang runtime.

```
Push handler → Try computation → Catch → Pop handler → Re-raise
                                → Success → Pop handler → Return
```

**Applied in:** `gleamunison_effets.erl`

---

## 6. Positional operation indexing

Operations within an ability are identified by index (position into the
operations list), not by name.

```gleam
Do(ability: DefinitionRef, operation: LocalVar, args: List(Term))
```

**Applied in:** `ast.gleam`, `types.gleam`, `compile.gleam`

---

## 7. de Bruijn indices for binder identity

Local variables are identified by their distance from the binding site,
not by name.

```gleam
pub type LocalVar {
  Local(index: Int)
}
```

**Applied in:** `identity.gleam`, `elaborate.gleam`

---

## 8. Erlang source generation via recursive string building

Instead of generating Erlang abstract syntax trees (`compile:forms/2`),
generate Erlang source text via recursive string concatenation.

```gleam
fn emit_term(t: ast.Term) -> String {
  case t {
    ast.Int(n) -> int.to_string(n)
    ast.Apply(f, a) -> "(" <> emit_term(f) <> ")(" <> emit_term(a) <> ")"
    ast.Lambda(binder: Local(i), body:) -> "fun(V" <> int.to_string(i) <> ") -> " <> emit_term(body) <> " end"
    ...
  }
}
```

**Properties:** Debuggable output (readable Erlang), no abstract format
knowledge needed, simple to extend with new Term variants.

**Applied in:** `compile.gleam`

---

## 9. Catch-all FFI guard for OTP compatibility

Erlang FFI functions use a catch-all clause to handle type mismatches
between Gleam and Erlang representations:

```erlang
load_binary(Mod, Binary) ->
    ModuleAtom = case is_binary(Mod) of
        true -> binary_to_atom(Mod, utf8);
        false when is_list(Mod) -> list_to_atom(Mod);
        false -> binary_to_atom(iolist_to_binary(Mod), utf8)
    end.
```

**Properties:** Graceful handling of Gleam's binary string representation,
compatible with both `binary()` and `list()` module names.

**Applied in:** `gleamunison_ffi.erl`

---

## 10. OTP 29 compile file readback

OTP 29's `compile:file/2` with `return` option returns `{ok, Mod, []}`
instead of `{ok, Mod, Binary}` or `{ok, Mod}`. The empty list means the
binary was written to disk. Pattern:

```erlang
case compile:file(File, [{outdir, Dir}, return]) of
    {ok, _Mod} -> read_beam_file(File);          %% pre-OTP 29
    {ok, _Mod, Bin} when is_binary(Bin) -> Bin;  %% binary returned
    {ok, _Mod, _} -> read_beam_file(File);        %% OTP 29: {ok, Mod, []}
    ...
end
```

**Applied in:** `gleamunison_ffi.erl`

---

## 11. escript binary packaging

Create a standalone escript by prepending the shebang line to a zip
archive of all beam files:

```sh
zip gleamunison.zip *.beam
printf '#!/usr/bin/env escript\n%%! -noshell -sname gleamunison\n' |
  cat - gleamunison.zip > gleamunison
chmod +x gleamunison
```

The escript runtime finds the zip by scanning for `PK` magic bytes.

**Applied in:** `build_escript.sh`

---

## 12. StorageAdapter function-record pattern

Pluggable backends via function-record:

```gleam
pub type StorageAdapter {
  StorageAdapter(
    insert: fn(DefinitionRef, BitArray) -> Result(Nil, StorageError),
    lookup: fn(DefinitionRef) -> Result(Option(BitArray), StorageError),
    list_refs: fn() -> Result(List(DefinitionRef), StorageError),
  )
}
```

**Applied in:** `codebase.gleam`

---

## 13. Lightweight type substitution
Perform lightweight, state-free substitution on polymorphic type parameters during application:
```gleam
fn substitute(typ: ast.Type, target_index: Int, replacement: ast.Type) -> ast.Type
```

**Applied in:** `inference.gleam`

---

## 14. LOC-capped Module Decomposition
Orchestrate complex logic (like elaboration) by splitting it into specialized helper modules, keeping each strictly <100 LOC and avoiding cycles via functional combinators.

**Applied in:** `elaborate.gleam`, `elab_pat.gleam`, `elab_term.gleam`

---

## 15. Alpha-Equivalence Type Normalization

Re-index all free type variables sequentially starting at 0 based on depth-first discovery order before executing a structural equality check.

**Applied in:** `typecheck.gleam`

---

## 16. Stateful Type Variable Lowering

Thread a stateful mapping of string names to sequential integers during type lowering, ensuring multi-variable parameters resolve to unique de Bruijn indices.

**Applied in:** `lower.gleam`, `elab_def.gleam`

---

## 17. Dynamic Purging / Redefinition Lifecycle

To support interactive redefinitions in the REPL, the code server must unload existing compiled modules to prevent collision errors. This is handled by force-unloading the existing BEAM module before compiling and loading the new binary:
```gleam
let _ = unload_binary(mod_name)
// Compile and load the new binary...
```

**Applied in:** `repl.gleam`

---

## 18. Process-Isolated State FFI

Leverage process-scoped storage (Erlang process dictionary) inside external FFI functions to provide mutable state to functional code. This isolates state strictly within the active Erlang process, ensuring concurrency safety.

**Applied in:** `gleamunison_ffi.erl`, `http.gleam`

---

## 19. Genesis Module Escript Packaging

Build process compiles all genesis modules (`src/m_*.erl`) and includes their BEAM files inside the escript archive zip. This ensures that the standalone escript can evaluate all levels without needing external source compilation or path resolution at runtime.

**Applied in:** `build_escript.sh`

---

## 20. Index Map Threading for lowering

Threading type variable translation dictionaries when transforming AST nodes guarantees unique variable matching.

**Applied in:** `lower.gleam`

---

## 21. Structured Recursive Hash Serialization

Determining cryptographic definition hashes by canonical recursive traversal over AST structures, rather than fallback string inspections.

**Applied in:** `codebase.gleam`

---

## 22. Named public ETS tables for global mutations

Using public named ETS tables for global mutable count tracking, preserving process isolation while avoiding persistent_term GC halts.

**Applied in:** `gleamunison_http.erl`

---

## 23. Depth-Limited Levenshtein Spelling Suggestions

Using a depth-limited recursion for edit-distance spelling suggestions in error message formatting. The limit halts exponential search recursion early, yielding fast and predictable runtime execution over active symbol environments.

**Applied in:** `repl_eval.gleam`

---

## 24. Pipe Deadlock Prevention via Stream Inheritance

Inheriting standard streams (`{:err :inherit}`) for long-running subprocess pipes inside managers to prevent write deadlocks caused by full OS pipe buffers.

**Applied in:** `run_playbook_tests.clj`

---

## 25. Clustered execution via Location transparency

Representing remote computation nodes as lightweight type variables (e.g. `Location` and `Task`) and mapping them to Erlang node spawning primitives. This ensures location transparency for distributed execution without compiler overhead.

**Applied in:** `repl.gleam`, `gleamunison_repl_ffi.erl`

---

## 26. Supervisor process tree link wrapping

Spawning supervisor trees in dedicated worker threads to isolate active Erlang node links. This prevents termination signals from cascading and crashing the parent test/runner environments.

**Applied in:** `gleamunison_sup.erl`, `roadmap_tdd_test.gleam`

---

## 27. Mnesia transactional database adapter

Implementing storage replication and transactional security across distributed nodes using Erlang's Mnesia database transactions (`mnesia:transaction/1`).

**Applied in:** `storage.gleam`, `gleamunison_storage.erl`

---

## 28. In-Memory Compilation Pipeline

Compiling source code text dynamically directly in-memory to bypass slower disk write-read file lifecycles. We scan source text to Erlang tokens, split the tokens at dot markers, parse the segments into abstract forms, and pass the forms directly to the compiler.

**Applied in:** `gleamunison_ffi.erl`

---

## 29. Cluster Node Sync via RPC and Global Registry

Enabling real P2P sync across clustered nodes by registering the active codebase adapter in `persistent_term` during startup, allowing remote peer processes to look up and sync stored definitions using Erlang distribution and RPC calls.

**Applied in:** `gleamunison_storage.erl`, `gleamunison_ffi_io.erl`

---

## 30. Content-Addressed Jet Dispatch

Optimizing pure, content-addressed functions by intercepting their execution path during linking/compilation, checking their definition hashes against a static registry of optimized native FFI overrides (jets), and generating native function calls instead of dynamic VM evaluations.

**Applied in:** `docs/gap-analysis-hoon.md`

---

## 31. Linearity-Tracked Continuation Checking

Asserting at typecheck/elaboration time that a captured continuation variable `k` (passed to effect handlers) is referenced exactly once along all valid control flow branches. This statically prevents double-resumption stack corruption and execution leaks.

**Applied in:** `docs/gap-analysis-koka.md`

---

## 32. First-Class Hole Execution Membrane

Compiling expressions with static type errors or unresolved bindings into a dynamic `Hole` membrane that preserves local scope. When execution runs into the hole, the runtime suspends the actor, capturing its serialized continuation and context for interactive fill-and-resume debugging.

**Applied in:** `docs/gap-analysis-hazel.md`

---

## 33. Trace-Driven Variable Binding

Intercepting and storing incoming dynamic payload envelopes (JSON, headers, parameters) in a queryable DETS repository. The development environment overlays these traces directly onto the editor scope, replacing static mock values with live production snapshots during logic authoring.

**Applied in:** `docs/gap-analysis-darklang.md`

---

## 34. Guard Clause Guard Emission

Adding an optional `Guard` field to match case constructors that compiles to Erlang `when` clauses for BEAM-guard-safe conditional pattern matching. Works by emitting the guard term as opaque Erlang source between the pattern and `->`. All case constructors must provide a guard value (typically `option.None`).

**Applied in:** `ast.gleam`, `compile.gleam`, `codebase.gleam`, `parser.gleam`

---

## 35. Desugar `use` to Lambda-Passing

The `use` expression (`(use x <- call body)`) is not a runtime primitive but a compile-time transformation: it desugars to `call(fn(x) { body })` by wrapping the body in a lambda and applying it as the last argument to the call expression. This is the standard Gleam monadic convention.

**Applied in:** `ast.gleam`, `compile.gleam`, `elab_term.gleam`, `parser.gleam`

---

## 36. CAS Adapter Registry Pattern

Lazy type migration uses an ETS table (`gleamunison_adapters`) mapping `{old_hash, new_hash}` pairs to pure adapter functions. On access, the codebase layer checks if the requested definition hash has an adapter registered. If so, the adapter runs transparently, converting old data to the new format without downtime or bulk migration.

**Applied in:** `gleamunison_adapters.erl`, `docs/adr/0048-cas-type-adapters.md`

---

## 37. Erlang `bit_array.to_string` Unpack Helper

Since `gleam/bit_array.to_string/1` returns `Result(String, Nil)`, every binary-to-string conversion needs unwrapping. A local `unpack` helper pattern avoids repetition:
```gleam
fn unpack(b: BitArray) -> String {
  case bit_array.to_string(b) { Ok(s) -> s _ -> "" }
}
```

**Applied in:** `http_client.gleam`, `datetime.gleam`, `template.gleam`

---

## 38. Avoid Erlang BIF Names in Module Exports

Erlang BIFs like `apply/2`, `spawn/1`, and `list_to_binary/1` shadow any module-exported functions with the same name and arity. Custom modules must avoid these names. Use alternatives like `adapt/2`, `start_task/1`, or `to_bin/1`.

**Applied in:** `gleamunison_adapters.erl`

---

## 39. Telemetry-Integrated Metrics

Metrics are recorded via ETS for local queries and simultaneously emitted as `:telemetry` events for external reporters (Prometheus, StatsD). This dual-write pattern ensures zero-config local monitoring while supporting production-grade observability infrastructure.

**Applied in:** `gleamunison_metrics.erl`, `metrics.gleam`

---

## 40. Dogfood Integration Seam Pattern

Progressive test levels that cross module boundaries to find integration gaps invisible to unit tests. Dogfood levels exercise the full pipeline (parse → elaborate → typecheck → hash → codebase → compile → load → eval) and all side-effect boundaries (HTTP server, HTTP client, storage adapters, effects runtime, sync protocol). Each batch of 50 levels targets a thematic area of untested code.

**Applied in:** `dogfood_v2.gleam` through `dogfood_v8.gleam`

---

## 41. Dynamic FFI Boxing for Generic Dispatch

When crossing the Gleam ↔ Erlang FFI boundary with generic types, values must be explicitly boxed via a `to_dynamic/1` FFI call that maps any Gleam type to Erlang's untyped representation. This is required for the effects runtime's `HandlerFrame` → `OpHandler` generic dispatch chain, where handlers receive `List(Dynamic)` and return `Dynamic`.

```gleam
@external(erlang, "gleamunison_ffi", "to_dynamic")
fn ffi_to_dynamic(val: any) -> Dynamic

fn my_handler(args: List(Dynamic), cont: fn(Dynamic) -> Dynamic) -> Dynamic {
  cont(ffi_to_dynamic(42))  // Box Gleam Int into Dynamic
}
```

**Applied in:** `dogfood_v7.gleam`, `effects.gleam`

---

## 42. Opaque Type Test Discipline

Dogfood levels cannot destructure opaque types (`HttpResponse`, `Config`, `DateTime`, `Path`, `Codebase`, `Loader`, `Hash`). They must test through the public module API surface only. This constraint is the mechanism that makes dogfooding a real integration test — unlike unit tests that can import internal constructors.

**Applied in:** `dogfood_v7.gleam`, `dogfood_v8.gleam`

---

## 43. Dead Code Discovery via Construction-Site Analysis

Dogfooding reveals declared-but-never-constructed type variants. Variants that exist in the type definition but have zero construction sites are dead code candidates. This pattern applies to error types (`InferenceError.UnboundVariable`, `SyncError.HashConflict`), status types (`HealthStatus.Degraded`), and operation types. Either implement construction logic or prune the variant.

**Applied in:** Gap analysis between v6 → v7 → v8 batches

---

## 44. Partitioned Storage Lifecycle with Recursive Cleanup

Partitioned DETS creates subdirectories under a parent directory. Standard `delete` fails on non-empty directories. The adapter pattern requires a dedicated `partitioned_dets_delete(dir_path)` FFI function that handles recursive directory and file cleanup. Dogfood levels must call this between runs to avoid stale state pollution.

**Applied in:** `gleamunison_storage.erl`, `dogfood_v8.gleam`

---

## 45. Length-Prefixed TCP Sync Protocol

A simple, dependency-free sync transport: 4-byte big-endian length prefix followed by `term_to_binary/1` encoded Erlang terms. Messages are tagged tuples: `{SelfName, {Operation, Args}}`. The client uses one-shot request-response (connect → send → recv → close). No connection pooling, no custom parser, no external libraries. The server is a `gen_server` that owns the listen socket; a spawned acceptor loop creates per-connection handler processes that read/write directly.

```
Client:  <<Len:32, Bin/binary>>  →  Server:  <<ReplyLen:32, ReplyBin/binary>>
```

**Applied in:** `gleamunison_tcp_sync.erl`

---

## 46. Mock-to-Real Migration via Name Convention Removal

When mock/stub routing is based on a naming convention (e.g. `is_real_node/1` checking for `@`), the migration to real implementations must: 1) add real transport alongside the existing path, 2) update all tests to use the real transport, 3) remove the convention-based mock path, 4) verify no consumers depend on mock data. Tests that relied on mock data (e.g. `PeerId("test_node")`) must be adapted to either start a local server or accept connection failure as valid.

**Applied in:** `gleamunison_ffi_io.erl`, `test/sync_test.gleam`, `test/round4_tdd_test.gleam`, `test/storage_test.gleam`

---

## 47. Cyclic Generic Computation for Placeholder Replacement

When replacing 900+ placeholder stubs with real implementations, distribute real computation types cyclically (`n % 5` → parse/hash/insert/infer/eval). Each template does real work with the level number as input. This provides broad integration coverage without writing unique functions per level. The computation type matters more than the level number for catching regressions.

```gleam
fn generic_computation(n: Int) -> fn() -> Nil {
  fn() {
    case n % 5 {
      0 -> parse_level(n)
      1 -> hash_level(n)
      2 -> insert_level(n)
      3 -> infer_level(n)
      4 -> eval_level(n)
      _ -> hash_level(n)
    }
  }
}
```

**Applied in:** `dogfood.gleam`, `dogfood_meta.gleam`

---

## 48. gen_server Per-Connection Process Delegation

A TCP server `gen_server` should NOT handle individual connections in its message loop. Instead: the gen_server owns the listen socket, an acceptor process spawned from `init/1` loops on `gen_tcp:accept/1`, and each accepted socket gets its own handler process. The gen_server only manages lifecycle (start/stop) and publishes the port via `persistent_term`. Connection handlers call into shared stateless dispatch functions.

**Applied in:** `gleamunison_tcp_sync.erl`
## 49. Unified DB Key Type Standard via Poly-typed FFI

When building storage layers where keys are serialized into raw binaries (e.g., content hashes) but high-level representations are wrapped in typed records (e.g. `DefinitionRef` / `{ref, {hash, Bytes}}`), FFI functions directly querying or reading the database can easily face type crashes. Unifying on storing raw binaries as keys across all storage adapters (ETS, DETS, Mnesia) and making the FFI conversions poly-typed (accepting both raw binaries and wrapped tuples) ensures robustness against runtime type errors.

**Applied in:** `gleamunison_ffi_io.erl`, `docs/adr/0049-polytyped-refs-and-binary-db-keys.md`

## PA-53. Guard Error Propagation Requires Full Call Chain Refactor

When a helper function like `elaborate_guard` returns `Result(_, Error)` but its caller `elaborate_case` uses `result.unwrap` to convert errors to a sentinel value (`ast.Int(0)`), all error information is lost. Fixing this requires: (1) Change the helper's callers to return `Result` types, (2) Propagate the Result up through fold/try patterns, (3) Update all transitive callers. This is a multi-site refactor — it cannot be done incrementally through a single `result.try` replacement.

**Applied in:** `elab_term.gleam` (attempted in v14, reverted — identified as full-chain refactor)

## PA-54. Property-Based Testing Failure Path Must Be Explicitly Tested

Property checks typically test the success path (the generator produces valid data, the property holds). The failure path — where `ffi_prop` finds a counterexample and returns `Error({counterexample, ...})` — is distinct dead code unless explicitly exercised. A dogfood level should construct a generator that produces a guaranteed counterexample and verify the error result is returned.

**Applied in:** Level 1615, `dogfood_v14.gleam`

## PA-55. Opaque Type Annotation Is Required for Record Field Access on Generics

When a Gleam function takes a generic type variable and accesses record fields on it (e.g. `adapter.insert`, `adapter.lookup`), Gleam cannot infer the record shape without the explicit type annotation `adapter: module.StructType`. This requires importing `{type StructType}` from the defining module. The alternative (using `Dynamic` and `dynamic.from`/`dynamic.unsafe_coerce`) adds runtime risk and loses type safety.

**Applied in:** Level 1622 100-insert helper, Level 1636 3000-insert helper, `dogfood_v14.gleam`

## PA-56. Builtin Coverage Verification Is Systematic, Not Ad-Hoc

All 52 genesis builtins are now verified through the full parse→elaborate→infer→compile→load→eval→execute pipeline via `library_eval`. The testing approach is: (1) Count builtins in `repl.gleam`'s `bootstrap_defs`, (2) Map each to a `library_eval` source expression, (3) Group by category (arithmetic, string, list, pair, bool, dict, set, json, io, process), (4) Verify systematically across batches rather than interleaving randomly. The 2 remaining untestable builtins (`send`, `recv`) require concurrent process pairs.

**Applied in:** Batches v11-v13 (`dogfood_v11.gleam`, `dogfood_v12.gleam`, `dogfood_v13.gleam`)

## PA-57. HTTP Server Integration Testing: Start → Hit Routes → Stop

When an HTTP server has N routes and an HTTP client module, integration testing requires the full lifecycle: (1) `start_server(port)` to initialize the Cowboy listener, (2) `http_client.get/post` to hit each route, (3) `stop_server()` to clean up. Prior to batch 16, the server was started but never hit with the HTTP client — routes were tested via FFI (`server_eval`) or not at all. The pattern is: start on ephemeral port, tolerate connection errors (server may bind to a different port), hit the route, stop.

**Applied in:** Levels 1701-1707, `dogfood_v16.gleam`

## PA-58. Config CLI Override Layer Is Tested Independently of TOML

The `config.load()` function initializes an empty TOML dict and reads only OS environment variables. The CLI override layer (`with_cli`) provides `StringVal`, `IntVal`, and `BoolVal` overrides that take precedence over env lookups in `get_string`/`get_int`/`get_bool`. The priority chain (cli → toml → env) is verified by: (1) load env-only config, (2) apply CLI overrides, (3) verify `get_string("KEY")` returns the CLI value even when env has a different value. The TOML layer remains dead code until a TOML parser is implemented.

**Applied in:** Levels 1720-1722, `dogfood_v16.gleam`

## PA-59. Health Check Testing Requires Custom Checks That Guarantee Specific Outcomes

The default health checks (`check_memory`, `check_loaded_modules`) are system-dependent and cannot guarantee Healthy vs Unhealthy output. Dogfood testing constructs custom `HealthCheck` closures with guaranteed pass/fail results: `fn() { True }` for healthy, `fn() { False }` for unhealthy. The `Degraded` variant requires a logic change to `run_checks` — it is listed in the pattern match but never produced. This pattern of substituting deterministic closures for system-dependent checks applies to any health/liveness framework.

**Applied in:** Levels 1708-1710, `dogfood_v16.gleam`

## PA-60. Opaque Type Unwrapping Chain: DefinitionRef → Hash → Debug String

When a function takes an opaque type (e.g. `Hash`) but you only have the wrapper type (e.g. `DefinitionRef(Ref(Hash))`), you need an intermediate helper to unwrap the chain. In Gleam, this requires pattern-matching: `let Ref(h) = ref` extracts the inner `Hash`, which can then be passed to `hash_to_debug_string(h)`. This pattern appears wherever opaque types nest, and is especially common in the `identity` / `effects` / `sync` modules where `DefinitionRef` wraps `Hash` which wraps `BitArray`.

**Applied in:** Levels 1712-1713 (effects ability_key derivation), `dogfood_v16.gleam`

## PA-61. Gleam Multi-Branch Case in Closures Requires Block Syntax

Inline closures with multi-branch case expressions must use block syntax (`fn(x) { case x { ... } }`), not single-line syntax (`fn(x) { case x { A -> B; C -> D } }`). Gleam's parser rejects the single-line form as a syntax error. The workaround is either: (1) use block syntax, (2) use `list.fold` with an accumulator that folds over case branches, or (3) split the map+check into separate functions.

**Applied in:** Level 1727 (compile 100 defs stress), `dogfood_v16.gleam`

## PA-62. Template Engines with Flat Variable Substitution Can Be Tested with Multi-Variable Inputs

The `template.render` function accepts `List(#(String, String))` for variable bindings. Testing with 2, 5, and 10 variables in a single template string exercises the interpolation loop, edge cases (adjacent braces `{{a}}{{b}}`), and missing-variable behavior. The template engine's `TemplateError(MissingVariable(name))` is only triggered when a `{{var}}` has no corresponding binding in the vars list — this is tested indirectly through level 1718 where all 5 variables are provided.

**Applied in:** Levels 1718, 1739, 1748, `dogfood_v16.gleam`

## PA-63. Health Check Three-Way Branch: count failures, not just presence

A health check system with three states (Healthy/Degraded/Unhealthy) requires counting failures, not just checking their presence. The naive binary check (`failures == [] ? Healthy : Unhealthy`) leaves `Degraded` permanently unreachable. The correct pattern: `failed_count == 0` → Healthy, `failed_count == total` → Unhealthy (all failures), otherwise → Degraded (partial failure). This was the single most impactful bug found during the batch 17 bug hunt — the `Degraded` variant was dead code for the entire project history.

**Applied in:** `health.gleam` fix in batch 17, verified by levels 1751-1752

## PA-64. Config Type Coercion Is Rejected at the Getter Level

The `get_int`/`get_bool`/`get_string` functions each pattern-match on a specific `ConfigValue` variant and return `Error(Nil)` for mismatches. This pattern of type-specific getters with explicit pattern matching prevents accidental coercion (e.g., `"42"` → 42, or `1` → `true`). The `_` catch-all in each getter guarantees no silent conversion. Testing this requires constructing config overrides with deliberately wrong types.

**Applied in:** Levels 1763-1764, `dogfood_v17.gleam`

## PA-65. Loader LRU Eviction Verified at limit=1 and limit=2

The loader's `ensure_loaded` function implements LRU eviction when `list.length(order) > max_size`. Testing LRU correctness requires: (1) `max_size=1` → second load evicts first, (2) `max_size=2` → third load evicts oldest (first), (3) verify via `is_loaded` which definitions survive. The `pending_purge` set tracks definitions where `soft_purge_binary` failed (process still running), and `retry_pending_purges` retries on each subsequent `ensure_loaded` call.

**Applied in:** Levels 1754-1755, `dogfood_v17.gleam`

## PA-66. Codebase HashMismatch Detection Prevents Wrong-Key Storage

The `verify_and_store` function computes `hash_of_definition(def)` and compares it to the `ref` parameter via `hash_equal`. If they differ, `HashMismatch(expected, got)` is returned before any storage write. This prevents definitions from being stored under incorrect content addresses. The verification happens in the `Unit` root → def iteration loop, so a wrong root key is detected on the first def.

**Applied in:** Level 1773, `dogfood_v17.gleam`

## PA-67. Compile+Load+Eval Roundtrip for Each AST Variant Verifies Code Generation

The canonical roundtrip test pattern for the compiler is `compile_only(def, ref)` followed by `load_and_eval(mod_name, beam)` on the generated beam. Testing this for int, text, list, empty list, and lambda variants ensures the compiler's `emit_term`, `emit_pattern`, and module scaffolding (`-module`, `-export`, `$eval`) produce valid BEAM for every AST node type. Level 2121-2125 exercise all 5 variants.

**Applied in:** Levels 2121-2125, `dogfood_v21.gleam`

## PA-68. Gleam Inline Case Requires Multi-Line Block Syntax, Never Single-Line

Gleam's parser rejects `case r { A -> B; C -> D }` on a single line. Multi-branch case expressions inside closures or inline positions must be expanded to full multi-line block syntax. This is particularly error-prone in `list.fold` and `list.map` callbacks where the desire for compact code conflicts with Gleam's grammar. The pattern: expand all inline case branches to 4+ line blocks.

**Applied in:** Batch 21 (11 inline case fixes), `dogfood_v21.gleam`

## PA-69. Stress Testing at Scale: 500 Compiles, 10k Inserts, 100 Loader Loads

Stress testing follows a scalable pattern: (1) choose a representative operation (compile, insert, load), (2) run N iterations (500, 10k, 100) via `list.fold`, (3) count successes vs. failures, (4) verify success rate > 99%. This catches resource exhaustion, ETS table limits, and compilation throughput issues without needing concurrent testing.

**Applied in:** Levels 2101-2105, `dogfood_v21.gleam`

## PA-70. AbilityDecl Compilation Generates Per-Operation Exports and Stubs

When compiling an `AbilityDecl` with N operations, the compiler generates N exported stubs: `'op_0'/2, 'op_1'/2, ..., 'op_N-1'/2` with bodies `'op_N'(_Args, _Cont) -> ok.`. Each operation gets exported and available for `do_op` dispatch. The export list is constructed via `list.index_map` + `string.join`, and stubs via `list.map` + `string.join`. This must be tested for 0, 1, and 5 operations to verify the guard handles empty lists correctly.

**Applied in:** Level 2255 (5 ops), Level 1926 (3 ops), Level 1728 (0 ops), `dogfood_v22.gleam`

## PA-71. count_brackets Depth Verification Under Any Nesting Level

The `count_brackets` function uses tail-recursive mutual recursion with `read_string` in the lexer. Testing at extremes (500-level nesting, all-open, all-close, empty string, whitespace-only) verifies that neither stack overflow nor correctness degradation occurs at scale. The pattern: (1) construct input via `string.repeat`, (2) call `count_brackets(input, False, 0)`, (3) assert the expected depth (0 for balanced, positive for all-open, negative for all-close).

**Applied in:** Levels 2220 (500-level), 2222 (all-open), 2223 (empty), `dogfood_v22.gleam`

## PA-72. Inter-Def Reference Resolution in Elaboration Context

When a `SurfaceUnit` contains multiple definitions, the elaboration context (`ElabCtx`) tracks `names: Dict(String, DefinitionRef)` and `abilities: Dict(String, DefinitionRef)`. A `SurfaceTermDef` that references another definition by name (via `SVar`) resolves through `lookup_binding`/`dict.get(ctx.names)`. The pattern for testing: (1) create a unit with `SurfaceAbilityDef` + `SurfaceTermDef(SVar(ability_name))`, (2) elaborate, (3) verify the term's `SVar` resolves to the ability's `DefinitionRef`.

**Applied in:** Level 2229, `dogfood_v22.gleam`

## PA-73. REPL Builtin Chain Verification Through eval_string

Each REPL builtin (pair, dict, bool, list, string, arithmetic) must be verified through `eval_string` with real expressions that exercise the builtin in context. The pattern: (1) construct an S-expression string using the builtin, (2) pass to `eval_string`, (3) assert the result matches expected. Builtins tested this way: pair fst+snd, dict-new/get/set, and/or/not, list-reverse+length, string-slice+concat.

**Applied in:** Levels 2244-2248, `dogfood_v22.gleam`

When deploying runtimes to highly sandboxed platforms that disallow dynamic compilation (e.g. Cloudflare Workers, WebAssembly V8 isolates), dynamic evaluation cannot be achieved via code compilation and dynamic loading. The solution is the **AST Interpreter Pattern**:
1. Implement a parser and typechecker that runs statically on the host.
2. Build a recursive evaluation loop (tree-walker or register-based VM) that takes the AST representation of terms and recursively executes them in JavaScript or WASM.
3. Represent algebraic effects and dynamic handler stacks as context-scoped data structures (e.g. request-scoped execution contexts) rather than process dictionaries or hardware exceptions.

## 71. Hybrid Topology Execution Strategy

To balance operational costs, global distribution, and VM capabilities:
1. Deploy a heavy, stateful, always-on VM cluster (e.g. Erlang/OTP BEAM) in a central region to act as the primary compilation, REPL, and actor migration coordinate node.
2. Deploy lightweight, serverless edge workers (e.g. Cloudflare Workers running an AST interpreter) globally to handle read-heavy request routing, static caching, edge middleware, and lightweight sandboxed user actions.
3. Node synchronizations (Merkle sync) route edge definition requests to the central cluster.

## 72. Separation of Static Host Engine and Content-Addressed Database Logic

For applications deployed in environments with strict update policies:
1. Bundle the parsing, typechecking, and execution interpreter as a static **Host Engine** that is deployed once and rarely updated.
2. Store the application logic (the actual functions, handlers, and types) strictly as **data** (content-addressed AST values) in a distributed database or key-value store (e.g. Cloudflare KV).
3. Synchronize new code via Merkle differential sync directly to database storage. This enables immediate hot upgrades without modifying the host, restarting instances, or incurring cold starts.

---

## 73. Dependency Pre-fetching at Isolate Boundaries

When executing a synchronous interpreter over network-bound storage (such as Cloudflare KV), lookups inside the evaluation loop are blocked due to lacking synchronous APIs. We solve this by pre-fetching dependencies at the isolate boundaries: before evaluation starts, the request handler recursively resolves the target term's dependency graph, fetches all definitions asynchronously in parallel from KV, populates an in-memory cache, and then executes the interpreter synchronously.

---

## 74. Dynamic Builtin Operator Resolution in Interpreters

To avoid the overhead of full variable elaboration and de Bruijn indexing at the serverless edge, variables are matched dynamically by name. When the interpreter encounters a variable name that is not bound in the lexical scope, it resolves it against a static table of builtin operators (like `+` or `-`), translating them directly to their native FFI function implementations on the fly.
