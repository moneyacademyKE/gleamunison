# Gap Analysis: gleamunison vs Hoon (Urbit)

A Rich Hickey-style Gap Analysis comparing the architectural paradigms of Urbit (Hoon/Nock/Arvo) with the Gleamunison runtime on the BEAM.

---

## 1. Feature Set Differences

| Feature | Urbit (Hoon/Arvo) | Gleamunison | Trade-off / Benefit |
|---|---|---|---|
| **VM Base** | Nock (12 instruction combinators) | BEAM (Erlang virtual machine) | Nock is mathematically minimal; BEAM is optimized, concurrent, and industrial-grade. |
| **Scoping** | Subject-Oriented (subject tree traversal) | Lexical (de Bruijn indexes) | Subject-oriented makes serialization trivial; Lexical compiles directly to fast BEAM variables. |
| **Optimization** | Jets (Native C/Rust overrides by battery hash) | Dynamic Compilation (AST compiled to BEAM) | Jets require manual FFI matching; BEAM compilers optimize arbitrary user-defined terms. |
| **State Model** | Event-Sourced Event Log (pure state replay) | Actor State (process dictionary, FFI) | Event log offers perfect time-travel replay; Actor state is faster and matches OTP paradigms. |
| **Storage** | Clay (Typed, revision-controlled filesystem) | DETS / Mnesia (Content-addressed CAS) | Clay has schema version control; DETS/Mnesia is low-overhead and supports ACID clusters. |
| **Networking** | Ames (Cryptographic P2P with Azimuth PKI) | Erlang Distribution / Sync Protocol | Ames is secure on the public internet; Erlang distribution is fast but requires private VPCs. |

---

## 2. Capability Deep Dive & Recommendations

### Concept A: Jetting Pattern (Optimization Override)
* **Urbit Concept**: Intercept execution of specific content-addressed formulas (by hash) and replace them with native, high-performance overrides (jets) in C/Rust.
* **Gleamunison Benefit**: Let developers write pure, auditable Gleamunison functions, but swap their execution at compile/link-time with optimized native Erlang/Gleam functions or C-NIFs (e.g. for cryptography or parsing).
* **Verdict**: **Adopt (High Priority)**. Can be implemented within the dynamic compiler (`gleamunison/compile`) by registering a map of `Hash -> ErlangModule/Function` bindings.

### Concept B: Deterministic Event Log (State Sourcing)
* **Urbit Concept**: System state is a pure function of historical events: `f(events) -> state`.
* **Gleamunison Benefit**: Stateful actors can log incoming messages alongside the handler's codebase hash. This enables deterministic replay, debugging, and auditability.
* **Verdict**: **Adopt (Medium Priority)**. Build as a library actor behavior inside the runtime.

### Concept C: Ames-style Cryptographic P2P Distribution
* **Urbit Concept**: All communications are encrypted, authenticated, and addressed by cryptographic identities.
* **Gleamunison Benefit**: Secures clustering and peer sync (`gleamunison/sync`) over the public internet, bypassing Erlang distribution's insecure shared cookies.
* **Verdict**: **Adopt (Medium Priority)**. Add ECDSA/Ed25519 signatures and symmetric encryption to the pull-sync and process communication layers.

---

## 3. Complexity vs. Utility

| Element | Complexity | Utility | Recommendation |
|---|---|---|---|
| **A: Compiler Jets** | Low | High | **Recommended**: Implement FFI mappings for specific hashes in the compiler. |
| **B: Event-Sourced Actor** | Medium | High | **Recommended**: Implement an event-logging actor wrapper for state replay. |
| **C: Cryptographic P2P** | Medium | High | **Recommended**: Secure sync and message FFI via asymmetric crypto. |
| **D: Clay Filesystem** | High | Medium | **Decline**: Keep DETS/Mnesia codebase; build directory mapping if needed. |
| **E: Subject Scoping** | High | Low | **Decline**: Retain fast lexical de Bruijn variables. |

---

## 4. Actionable Path
1. **Implement FFI Jets in Compiler**: Map critical core hashes to native Erlang modules in `compile.gleam`.
2. **Secure Peer-to-Peer Sync**: Upgrade FFI networking to sign and encrypt packet payloads.
3. **Event-Sourced Actors**: Design an algebraic effect or actor behavior that logs state mutations for replay.
