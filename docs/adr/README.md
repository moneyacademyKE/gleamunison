# Architectural Decision Record (ADR) Log

This log catalogs all architectural decision records (ADRs) for the `gleamunison` codebase in chronological order.

| ID | Title | Status |
|---|---|---|
| [ADR-0001](0001-content-addressed-identity.md) | Content-addressed identity separation | Proposed |
| [ADR-0002](0002-types-as-computed-metadata.md) | Types as part of definition identity (amended) | Amended |
| [ADR-0003](0003-genesis-builtins.md) | Genesis builtins over BuiltinRef | Proposed |
| [ADR-0004](0004-closure-passing-for-effects.md) | Closure-passing for effects | Proposed |
| [ADR-0005](0005-loader-decomposition.md) | Loader decomposition into three services | Proposed |
| [ADR-0006](0006-at-prefix-module-naming.md) | @-prefixed module naming (superseded) | Superseded |
| [ADR-0007](0007-pull-based-sync.md) | Pull-based node synchronization | Proposed |
| [ADR-0008](0008-process-dictionary-for-scope.md) | Process dictionary for dynamic scope stack | Proposed |
| [ADR-0009](0009-types-in-definition-hash.md) | Types are part of definition identity (supersedes 0002) | Accepted |
| [ADR-0010](0010-storage-adapter-pattern.md) | Storage adapter pattern (pluggable backend) | Accepted |
| [ADR-0011](0011-m-prefix-module-naming.md) | m_ prefix module naming (supersedes 0006) | Accepted |
| [ADR-0012](0012-otp29-compile-file-readback.md) | OTP 29 compile file readback pattern | Accepted |
| [ADR-0013](0013-escript-standalone-binary.md) | escript standalone binary packaging | Accepted |
| [ADR-0014](0014-structural-type-propagation.md) | Structural Type Propagation and Lightweight Substitution | Accepted |
| [ADR-0015](0015-ets-storage-adapter.md) | ETS-Backed Storage Adapter for Codebase Persistence | Accepted |
| [ADR-0016](0016-three-phase-sync.md) | Three-Phase Pull Sync Protocol | Accepted |
| [ADR-0017](0017-ets-table-ownership.md) | ETS Table Ownership and Background Holder Process | Accepted |
| [ADR-0018](0018-process-dictionary-effects-handler-stack.md) | Process Dictionary for Dynamic Effect Handler Stacks | Accepted |
| [ADR-0019](0019-alpha-equivalence-normalizer.md) | Alpha-Equivalence Normalization for Polymorphic Types | Accepted |
| [ADR-0020](0020-dets-persistent-storage-and-sha256-hashing.md) | DETS Persistent Storage, SHA256 Hashing, and S-Expression Parser | Accepted |
| [ADR-0021](0021-runtime-tradeoffs-and-robustness-safeguards.md) | Runtime Tradeoffs & Robustness Safeguards | Accepted |
| [ADR-0022](0022-safe-deployment-and-remote-synchronization.md) | Safe Remote Synchronization and Environment-Isolated Pushes | Accepted |
| [ADR-0023](0023-interactive-repl-and-curried-beam-emission.md) | Interactive REPL and Curried BEAM Emission | Accepted |
| [ADR-0024](0024-repl-purging-stateful-ffi-and-web-dashboard.md) | REPL Module Purging, Stateful/File FFI, and Dynamic Web Dashboard | Accepted |
| [ADR-0025](0025-lower-typecheck-module.md) | Code Deconstruction and Lowering-Typecheck Division | Accepted |
| [ADR-0026](0026-canonical-hash-serialization.md) | Canonical Binary Serialization for Hash Invariants | Accepted |
| [ADR-0027](0027-community-library-package-integration.md) | Integration of Community Library Packages | Accepted |
| [ADR-0028](0028-infinite-recursion-detection-in-shadowed-builtins.md) | Infinite Recursion Avoidance in Shadowed Builtins | Accepted |
| [ADR-0029](0029-state-ability-bootstrapping-and-handler-stack-composition.md) | State Ability Bootstrapping and Handler Stack Composition | Accepted |
| [ADR-0030](0030-curried-beam-list-fold-ffi-integration.md) | Curried BEAM List Fold FFI Integration | Accepted |
| [ADR-0031](0031-modular-ffi-decomposition-for-strict-compliance.md) | Modular FFI Decomposition for Strict Compliance | Accepted |
| [ADR-0032](0032-parser-string-escape-sequences-and-timeout-resilient-test-runner.md) | Parser String Escape Sequences and Timeout-Resilient Test Runner | Accepted |
| [ADR-0033](0033-spelling-suggestions-and-bracket-counting.md) | Spelling Suggestions and Bracket Counting | Accepted |
| [ADR-0034](0034-distributed-topology-and-concurrency.md) | Distributed Topology & Concurrency | Accepted |
| [ADR-0035](0035-lexer-parser-separation.md) | Lexer-Parser Separation | Accepted |
| [ADR-0036](0036-dogfood-benchmarking.md) | Dogfood Benchmarking Methodology | Accepted |
| [ADR-0037](0037-repl-eval-io-decomposition.md) | REPL Eval/IO Decomposition | Accepted |
| [ADR-0038](0038-type-pretty-module.md) | Type Pretty-Printing Module | Accepted |
| [ADR-0039](0039-in-memory-compilation-and-live-distributed-sync.md) | In-Memory Compilation and Live Distributed Sync | Accepted |
| [ADR-0040](0040-production-builtins-real-io-http.md) | Production-Grade Genesis Builtins (Real File I/O & HTTP) | Accepted |
| [ADR-0041](0041-robust-supervisor-testing-and-handler-validation-tradeoffs.md) | Robust Supervisor Testing & Handler Validation Tradeoffs | Accepted |
| [ADR-0042](0042-supervised-ets-ownership-for-peer-sync.md) | Supervised ETS Table Ownership for Peer Sync | Accepted |
| [ADR-0043](0043-dynamic-code-shipping-for-process-migration.md) | Dynamic Code Shipping for Process Migration | Accepted |
| [ADR-0044](0044-content-addressed-jet-registry.md) | Content-Addressed Jet Registry | Proposed |
| [ADR-0045](0045-linearity-enforced-single-shot-continuations.md) | Linearity-Enforced Single-Shot Continuations | Proposed |
| [ADR-0046](0046-first-class-typed-holes-and-dynamic-closures.md) | First-Class Typed Holes and Dynamic Closures | Proposed |
| [ADR-0047](0047-trace-driven-request-interception-and-analysis.md) | Trace-Driven Request Interception and Analysis | Proposed |
| [ADR-0048](0048-cas-type-adapters.md) | Lazy CAS Type Adapters | Accepted |
| [ADR-0049](0049-polytyped-refs-and-binary-db-keys.md) | Poly-typed References and Binary DB Keys | Accepted |
| [ADR-0050](0050-comprehensive-unit-test-coverage-expansion.md) | Comprehensive FFI Unit Test Coverage Expansion | Accepted |
| [ADR-0051](0051-strict-unterminated-string-literal-validation.md) | Strict Unterminated String Literal Validation | Accepted |
| [ADR-0052](0052-propagate-guard-elaboration-errors.md) | Propagate Case Guard Elaboration Errors | Accepted |
| [ADR-0053](0053-standardize-property-failure-path-and-types.md) | Standardize Property Failure Path and FFI Signatures | Accepted |
| [ADR-0054](0054-cloudflare-wasm-compatibility-analysis.md) | Cloudflare Workers and WebAssembly Compatibility Analysis | Accepted |
| [ADR-0055](0055-cloudflare-workers-hosting-topology.md) | Cloudflare Workers Hosting Topology Decisions | Accepted |
| [ADR-0056](0056-gleamunison-cloudflare-application-architecture.md) | Gleamunison Cloudflare Application Architecture Decisions | Accepted |
| [ADR-0057](0057-v3.4.0-gap-analysis.md) | v3.4.0 Rich Hickey Gap Analysis and Evolution Path | Accepted |
| [ADR-0058](0058-gleamunison-beam-vs-wasm.md) | Gleamunison BEAM vs. Cloudflare Workers WASM Decisions | Accepted |


