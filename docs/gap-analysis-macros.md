# Gap Analysis: gleamunison vs Macro Systems (Lisp, Clojure, Elixir)

A Rich Hickey-style Gap Analysis comparing macro expansion, compilation, and hygiene paradigms of Common Lisp, Clojure, and Elixir with the Gleamunison runtime.

---

## 1. Feature Set Differences

| Feature | Common Lisp | Clojure | Elixir | Gleamunison |
|---|---|---|---|---|
| **Syntax Style** | S-expression | S-expression | Infix (ast tuple representation) | S-expression |
| **Hygiene** | Unhygienic (manual `gensym`) | Semi-hygienic (namespace syntax-quote, `auto-gensym#`) | Hygienic by default (var contexts, `var!` override) | None |
| **Expansion Phase** | Read-time & Compile-time | Compile-time | Elaboration / Compile-time | None (straight compiler pipeline) |
| **Storage Model** | Source/In-memory AST | Source files / Class files | Source files / BEAM files | Content-addressed CAS (hash of elaborated AST) |
| **Metaprogramming** | Reader Macros & standard macros | Standard macros | Macro AST transformations | None |

---

## 2. Metaprogramming in Content-Addressed Systems

### The Merkle Constraint
In a content-addressed language runtime (like Unison or Gleamunison), definitions are identified by the cryptographic hash of their **elaborated, typed Core AST**.
* Macros are an **elaboration-time syntactic abstraction**.
* When a macro is expanded, it transforms an unevaluated S-expression into a standard S-expression/AST before hashing occurs.
* The codebase never stores the macro reference inside the hashed code; it only stores the fully expanded core term.
* **Benefit**: Macros are completely zero-cost at runtime and do not complicate the structural hashing model!

### Compilation and Hygiene Selection
* **Common Lisp**'s unhygienic macros are highly flexible but prone to accidental variable capture, requiring manual `gensym` bindings.
* **Clojure**'s syntax-quote qualifies symbols to their namespaces automatically, which prevents name collisions in a flat codebase.
* **Elixir**'s hygienic tuples are extremely safe but require complex compiler tracking of AST contexts.
* **Gleamunison Recommendation**: Implement a Clojure-style semi-hygienic system. Since we use de Bruijn indexing for local binders (`Local(index)`), variable capture within macro-expanded code is structurally neutralized at the name-resolution phase of the elaborator.

---
## 3. Paradigm Utility vs. Complexity Matrix

| Macro System Paradigm | Implementation Complexity | Developer Cognitive Complexity | Metaprogramming Utility | Suitability for Content-Addressed ASTs | Benefit / Trade-off |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **C Preprocessor (`#define`)** | Negligible | High (leaky, error-prone text replacement) | Low (restricted to token pasting/stringification) | None (destroys structured AST layout, un-hashable) | Simple text replacement, but lacks type or syntax awareness. |
| **Lisp Reader Macros** | Extreme | High (modifies parser behavior on the fly) | Maximum (can parse non-parenthesized custom syntaxes) | Very Low (complicates AST hashing and determinism) | Allows rewriting language syntax itself, but makes code parsing context-dependent. |
| **Standard S-expression Macros (`defmacro`)** | Low to Medium | Medium (straightforward list manipulation) | High (full program transformation using language itself) | Excellent (expanded away at elaboration time before hashing) | Easy syntax generation, but requires hygiene safeguards (e.g. `gensym`). |
| **Elixir AST-based Hygienic Macros** | High | High (non-homoiconic tuple representation) | High (structured code transformation) | Good (requires full syntax resolution beforehand) | Hygienic by default, but AST structure is complex to manually inspect/manipulate. |
| **Rust Procedural / Macro 2.0 Systems** | Extreme | High (requires separate crate compile step/token streams) | High (strong type-system guarantees and compile checks) | Good (expanded compile-time to typed tokens) | Extremely safe and powerful, but has huge tooling overhead. |

---

## 4. Trade-offs of Implementing Elaboration-Time Macros in Gleamunison

### A. Hash Stability vs. Macro Evolution (The "Semantic Drift" Trade-off)
* **The Choice**: Hashing only the fully expanded AST, rather than the macro invocation itself.
* **Pros**:
  * **Runtime Zero-Cost**: The macro definition is entirely compiled out before hashing. No macro execution footprint exists at runtime.
  * **Zero Dependency Conflicts**: Two modules utilizing different versions of a macro will hash to the exact same content-addressed ID if the expanded ASTs are identical.
* **Cons (Semantic Drift)**:
  * If you update a macro's implementation to generate different AST outputs (e.g., optimizing a loop macro), existing compiled definitions that *called* that macro will **not** automatically update their hashes or implementations. They must be explicitly re-elaborated and re-hashed to benefit from the new macro behavior, leading to potential semantic drift in the codebase database.

### B. Compile-Time Bootstrapping vs. Pipeline Performance
* **The Choice**: Dynamically compiling, loading, and executing macro code during the parser/elaborator phase.
* **Pros**:
  * Allows macros to perform arbitrary, powerful computations (e.g., compile-time HTTP requests, file reads, database lookups).
* **Cons**:
  * **Hot-Loading Overhead**: Elaboration speed will decrease significantly. For every macro execution, the runtime must: compile the macro S-expression to BEAM binary, hot-load the module, invoke it to expand the AST, and unload the transient BEAM module to avoid memory leaks.
  * **Phase Separation**: You cannot call a macro in the same file or compilation unit where it is defined, requiring strict module/file dependency sorting.

### C. de Bruijn Hygiene vs. Intentional Variable Capture
* **The Choice**: Relying on de Bruijn indices during name resolution to automatically enforce lexical hygiene.
* **Pros**:
  * **Implicit Hygiene**: Since the compiler translates name strings to relative index integers (`Local(index)`), variables defined inside a macro-expanded block cannot accidentally capture variables in the caller's lexical context.
* **Cons**:
  * **Loss of Context Modification**: It is difficult to implement macros that intentionally modify or inject bindings into the caller's scope (e.g., anaphoric `if` binding to `it`). Creating an "escape hatch" requires special parser tags that bypass name resolution, complicating the elaborator.

### D. Code Size in Database vs. Structural Sharing
* **The Choice**: Using macros to reduce source code boilerplate.
* **Pros**:
  * Vastly reduces the source-level verbosity of writing repetitive AST patterns.
* **Cons**:
  * In a content-addressed system, sharing is achieved by referencing identical AST sub-trees. If a macro is used to generate large, redundant code blocks inline instead of extracting them to reusable helper functions, the size of the serialized AST entries stored in the database increases.

---

## 5. Actionable Path
1. **Define `defmacro` Form**: Add a parser form `(defmacro name (args) body)` that registers the definition as a compile-time macro.
2. **Compile-Time Evaluation**: When the elaborator encounters a macro call, it compiles the macro to a BEAM module, loads it, calls it to expand the expression, and then continues elaborating the resulting AST.
3. **Hygiene via de Bruijn**: Rely on de Bruijn index assignment during the name-resolution phase of elaboration to guarantee lexical hygiene naturally.

