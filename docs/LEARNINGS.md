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
