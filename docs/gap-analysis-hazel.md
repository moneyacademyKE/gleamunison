# Gap Analysis: gleamunison vs Hazel

A Rich Hickey-style Gap Analysis comparing the architectural paradigms of Hazel (Typed Holes, Live Evaluation, CMTT) with the Gleamunison runtime on the BEAM.

---

## 1. Feature Set Differences

| Feature | Hazel | Gleamunison | Trade-off / Benefit |
|---|---|---|---|
| **Type Integrity** | Gradual Typing with holes (always typechecks) | Strict Hindley-Milner (fails on type mismatch) | Hazel allows running incomplete code; Gleamunison guarantees zero type errors before loading. |
| **Execution Model** | Continuous live evaluation (evaluation around holes) | Ahead-of-time/REPL compile and load | Hazel provides immediate feedback during editing; Gleamunison executes code only when fully specified. |
| **Hole Semantics** | First-class membranes with dynamic closures | Unrepresented (fails parser or compiler) | First-class holes preserve context for interactive debugging; Fails early is simpler for standard compiler flows. |
| **State Resumption** | Fill-and-Resume (resumes paused evaluation) | Hot module upgrades (state preservation in actor loop) | Resumption recovers specific call stacks; Hot upgrades swap the loop code but restart execution paths. |

---

## 2. Capability Deep Dive & Recommendations

### Concept A: First-Class Typed Holes (Membranes)
* **Hazel Concept**: A hole `?` represents missing code or a type inconsistency. Type checking resolves it as a gradual type, and execution evaluates around it. When executed, hitting a hole returns a hole closure (the environment and continuation at the hole).
* **Gleamunison Benefit**: Introduce a `Hole(name: String, env: Map(String, Term))` variant to `ast.Term`. If a type mismatch or missing definition is parsed, the elaborator compiles it into a `Hole` instead of failing.Holes compile to a runtime FFI handler `gleamunison:hole/2` that raises an algebraic effect or actor pause.
* **Verdict**: **Adopt (High Priority)**. Allows running and testing partially completed codebases, matching Unison's developer ergonomics.

### Concept B: Live Resumption (Fill-and-Resume)
* **Hazel Concept**: When a hole is filled, the runtime resumes execution from the exact hole continuation without restarting the program.
* **Gleamunison Benefit**: Because we have serializable continuations and process migration (Phase 5), when a running actor hits a `Hole` effect, it can serialize its continuation and suspend. When the developer fills the hole in the REPL or Web Dashboard, the runtime dynamically loads the new code and resumes the closure.
* **Verdict**: **Adopt (Medium Priority)**. Integrates perfectly with Phase 5 serializable continuations and Phase 6 Web Dashboard.

---

## 3. Complexity vs. Utility

| Element | Complexity | Utility | Recommendation |
|---|---|---|---|
| **A: First-Class Holes** | Medium | High | **Recommended**: Add `ast.Hole` variant and compile to runtime FFI. |
| **B: Dynamic Resumption** | Medium | High | **Recommended**: Reuse serializable closures to suspend/resume on holes. |
| **C: Gradual Type Semantics** | High | Medium | **Decline**: Keep HM typechecker; treat holes as polymorphic variables. |

---

## 4. Actionable Path
1. **Represent Holes in AST**: Add `ast.Hole(name: String)` and `ast.TypeHole`.
2. **Handle Holes in Compiler**: Emit `throw({hole_encountered, Name, Env})` or raise an algebraic effect when compilation reaches a hole.
3. **Dashboard Suspension UI**: Implement a debugger UI on the web dashboard to inspect active hole environments and dynamically inject code to resume the paused process.
