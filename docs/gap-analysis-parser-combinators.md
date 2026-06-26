# Rich Hickey Gap Analysis: S-Expression Parsing Strategies

This analysis evaluates different parsing methodologies for Gleamunison to identify the optimal balance between code size constraints, dependency overhead, and parser capabilities.

---

## 1. Feature Set Comparison

| Capability | Custom Recursive-Descent (Current) | Parser Combinators (e.g. Nibble) | Erlang Generators (leex/yecc) |
|---|---|---|---|
| **Lines of Code (LOC)** | **Low (~100 LOC)** | High (400+ LOC client code) | Medium (~150 LOC configuration) |
| **External Dependencies** | **None** | Requires 1+ Hex package (`nibble`) | None (Built-in to Erlang OTP) |
| **Error Reporting Quality** | Basic (Syntax error at token) | **Excellent** (Exact line/column) | Good (Parser syntax error info) |
| **Operator Precedence** | Manual/Implicit (Lisp-style lists) | **Built-in** (Pratt Parsing) | **Built-in** (Yacc-style declarations) |
| **Build & Toolchain** | Pure Gleam compiler | Pure Gleam compiler | Complex (Requires extra Erlang compile step) |
| **Backtracking Support** | Manual | **Automatic** | Automatic (LALR-1) |
| **Target Portability** | Erlang & JavaScript | Erlang & JavaScript | **Erlang Only** (fails on JS target) |

---

## 2. Detailed Trade-offs & Analysis

### Custom Recursive-Descent
* **Benefits**: 
  - Extremely compact: the entire lexer and parser fits in `parser.gleam` under 110 lines of code, well within our strict `<150 LOC` budget.
  - Zero dependencies: compile times are instant.
  - Native portability: works on any backend targets supported by Gleam.
* **Trade-offs**:
  - Very basic error messages.
  - S-expression structure is fixed; introducing infix operators (e.g. `1 + 2 * 3`) requires manual precedence sorting or pre-tokenizing logic.

### Parser Combinators (Nibble / Atto)
* **Benefits**:
  - Declarative monadic code block syntax.
  - Rich debugging error stacks out of the box.
  - Support for backtracking and Pratt parsing for infix expressions.
* **Trade-offs**:
  - **Dependency Pollution**: Fails our zero-dependency design target by pulling in Hex packages.
  - **LOC Expansion**: The composable wrappers expand the module source size, threatening our strict file size limit.

### Erlang generators (`leex` and `yecc`)
* **Benefits**:
  - Industrial-strength LALR parsing (same toolchain Erlang uses for its own parser).
  - Fast execution speed.
* **Trade-offs**:
  - **FFI Complection**: Ties the parser entirely to the Erlang backend, breaking future portability to JavaScript/Web browser sandboxes.
  - **Build Tool Complexity**: Compiling `.xrl` and `.yrl` files requires configuring build scripts to compile them before Gleam files.

---

## 3. Complexity vs. Utility Matrix

| Parsing Method | Complexity (1-5) | Utility (1-5) | Recommendation |
|---|---|---|---|
| **Recursive-Descent Parser** | 1 | 4 | **Maintain Current**: Highly cohesive, complies with file limits, zero dependencies. |
| **Parser Combinators (Nibble)** | 3 | 5 | **Avoid for now**: Useful for compiler-grade infix math, but brings package bloat and violates LOC caps. |
| **Erlang Generators (leex/yecc)** | 4 | 3 | **Avoid**: Complex build steps, binds project exclusively to Erlang target, breaking web goals. |

---

## 4. Actionable Recommendation

Keep the **Custom Recursive-Descent Parser** as the primary parser backend. Because Gleamunison's surface syntax is styled after Unison (which uses S-expressions), structural parentheses do the heavy lifting of establishing AST bounds. 

If infix operators or compiler-grade diagnostics become a primary requirement, we recommend migrating to **Parser Combinators** ONLY if the combinators can be written as a lightweight, private, dependency-free utility module in under 150 LOC.
