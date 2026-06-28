# Gap Analysis: gleamunison vs Koka

A Rich Hickey-style Gap Analysis comparing the architectural paradigms of Koka (Perceus, FBIP, Evidence Passing) with the Gleamunison runtime on the BEAM.

---

## 1. Feature Set Differences

| Feature | Koka | Gleamunison | Trade-off / Benefit |
|---|---|---|---|
| **Memory Model** | Perceus (Precise Reference Counting) | BEAM GC (Per-process generational GC) | Perceus has zero garbage collector pauses and precise deallocation; BEAM GC is highly concurrent and automated. |
| **Optimization** | FBIP (Functional But In-Place reuse analysis) | Immutable Erlang terms | FBIP yields native mutate-in-place speed; Erlang guarantees strict immutability but copies modified structures. |
| **Effects Compilation** | Evidence Passing (dynamic vector arguments) | Process Dictionary Stack | Evidence passing is purely functional and fast; Process dictionary stack is simple, idiomatic, and process-local. |
| **Continuations** | Linearity-tracked (single vs multi-shot) | Dynamic Erlang closures | Linearity tracking prevents double-resume bugs; Erlang closures are simpler to generate but allocate memory. |
| **Effect Typing** | Row Polymorphism (type-directed evidence) | Inferred requirements (row variables) | Koka's effect types map directly to code gen; Gleamunison uses requirements for safety boundaries. |

---

## 2. Capability Deep Dive & Recommendations

### Concept A: Evidence Passing (Tuple-Threaded Context)
* **Koka Concept**: Pass an "evidence vector" (handlers list) explicitly as an argument through every function. Lookups are fast, constant-time index lookups.
* **Gleamunison Benefit**: Instead of relying on Erlang's process dictionary (`$ability_stack`), we could thread the handler stack as a pure list/tuple argument in emitted Erlang code. This enables multi-fiber concurrency within a single BEAM process without state pollution.
* **Verdict**: **Adopt (Medium Priority)**. Enables pure functional, concurrent fiber scheduling on a single actor.

### Concept B: Linearity Tracking for Single-Shot Continuations
* **Koka Concept**: Type system tracks whether a continuation is called exactly once. Single-shot continuations skip stack copy allocations.
* **Gleamunison Benefit**: While the BEAM manages actual allocations, we can enforce single-shot constraints at the typechecker level to prevent double-resumes (which cause severe dynamic stack crashes in effect runtimes).
* **Verdict**: **Adopt (High Priority)**. Implement linear checking in the type checker.

### Concept C: FBIP / Reuse Analysis
* **Koka Concept**: If an immutable object's reference count is 1, compile updates to destructive in-place writes.
* **Gleamunison Benefit**: The BEAM's underlying Erlang VM does not allow mutating terms. However, for specialized types (e.g. a content-addressed database record or ETS-backed collections), we could apply in-place mutations if the variable is used linearly.
* **Verdict**: **Decline (Low Priority)**. Compiling this on top of BEAM immutability is extremely complex and offers limited utility compared to native ETS.

---

## 3. Complexity vs. Utility

| Element | Complexity | Utility | Recommendation |
|---|---|---|---|
| **A: Evidence Passing** | Medium | High | **Recommended**: Thread active handlers in generated function parameters. |
| **B: Single-Shot Types** | Medium | High | **Recommended**: Enforce linear continuation consumption in typechecker. |
| **C: FBIP for ETS** | High | Low | **Decline**: Keep standard ETS table operations for mutable states. |

---

## 4. Actionable Path
1. **Enforce Single-Shot Continuations**: Add a linearity pass to the type checker to assert that the continuation variable `k` is used exactly once in control flows.
2. **Evidence-Passing Compilation**: Modify the compiler (`compile.gleam`) to pass handler references as functional arguments, replacing the process dictionary lookup mechanism.
