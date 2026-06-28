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

## 3. Complexity vs. Utility

| Element | Complexity | Utility | Recommendation |
|---|---|---|---|
| **A: Elaboration-time Macros** | Medium | High | **Recommended**: Implement `defmacro` that compiles and executes S-expression generators at edit-time. |
| **B: Clojure-style Hygiene** | Low | High | **Recommended**: Solve scope clashes using de Bruijn name resolution during elaboration. |
| **C: Lisp-style Reader Macros** | High | Low | **Decline**: Keep the parser Lisp-style S-expressions simple. |

---

## 4. Actionable Path
1. **Define `defmacro` Form**: Add a parser form `(defmacro name (args) body)` that registers the definition as a compile-time macro.
2. **Compile-Time Evaluation**: When the elaborator encounters a macro call, it compiles the macro to a BEAM module, loads it, calls it to expand the expression, and then continues elaborating the resulting AST.
3. **Hygiene via de Bruijn**: Rely on de Bruijn index assignment during the name-resolution phase of elaboration to guarantee lexical hygiene naturally.
