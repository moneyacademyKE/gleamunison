# Production Roadmap

From architectural specification to production-grade content-addressed runtime.

**Current State:** Fully certified Lisp-style surface parser, typechecker, compiler, and VM runner. Certified against 1000 playbook conformance levels (959 passed, 41 skipped, 0 failed).

---

## Phase 0: Genesis bootstrap ✓
- **Status:** COMPLETE. Core pipeline compiles and executes.

## Phase 1: Core Language Runtime ✓
- **Status:** COMPLETE. Full term compilation, algebraic effects (Console, State), and handler stacks.

## Phase 2: Surface Language & REPL Tooling ✓
- **Status:** COMPLETE. S-expression parser, name resolution, error propagation, interactive REPL loop, and dynamic module hot-purging.

## Phase 3: Persistence & Sync Protocol ✓
- **Status:** COMPLETE. Durable DETS storage adapter, ETS table ownership, and pull-based peer synchronization.

## Phase 4: Production Hardening ✓
- **Status:** COMPLETE. SHA256 identity hashing, stack-safe effects FFI, and Algorithm W type propagation.

---

## Phase 5: Distributed Topology & Concurrency (Next Phase)

**Goal:** Turn Gleamunison into a multi-node, location-aware distributed cluster.

- **5.1 Distributed `Remote` Ability**: Add native support for location-based computation redirects:
  `remoteCompute : Location -> (() ->{Remote} a) ->{IO, Remote} a`
- **5.2 Serializable Continuations**: Capture stack-level execution checkpoints to resume suspended handler computations on remote BEAM nodes.
- **5.3 Mnesia storage cluster**: Add multi-node replicated database codebases using Erlang Mnesia instead of local DETS/ETS.
- **5.4 Supervision Trees**: Implement dynamic BEAM supervisors to hot-restart crashed actors while preserving stack-based handlers.

---

## Phase 6: Ecosystem & Developer Ergonomics

**Goal:** Enable product development and authoring tooling.

- **6.1 Package Registry**: P2P package manager verifying dependencies by hash.
- **6.2 LSP / IDE Support**: Autocomplete, definition jumps, and inline type annotation checks.
- **6.3 Dynamic Web Dashboard**: Full-fledged admin UI exposing syncing status, loaded modules, and hot-update analytics.
