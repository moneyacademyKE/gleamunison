# ADR-0059: gleamunison vs. Lean Lang Architectural Gap Analysis

## Context
As the `gleamunison` runtime matures, it is essential to evaluate it against other state-of-the-art general-purpose functional programming languages and verification environments. We conducted a Rich Hickey-style Gap Analysis to compare `gleamunison` (v3.4.0) with Lean 4 to determine if we should incorporate features such as dependent types, Functional But In-Place (FBIP) reference-counting, and metaprogramming macros.

## Decision
Based on our analysis of complexity vs. utility, we made the following decisions:
1. **Reject Dependent Types**: We will retain the decidable Hindley-Milner type system. Adding dependent typing (Calculus of Inductive Constructions) introduces excessive cognitive and compiler-level complexity that does not support our core goals of content-addressed distributed compute and hot-swapping.
2. **Reject FBIP Memory Management**: Lean 4's reference counting and destructive in-place updates are optimized for bare-metal systems. For `gleamunison`, we will continue to rely on the BEAM's native process-isolated garbage collector to preserve our dynamic sandboxing guarantees.
3. **Accept Monadic Syntactic Sugar**: We will adapt Lean 4's monadic scheduling ergonomics by implementing `let*` or `do` block bindings in our S-Expression elaborator, simplifying the sequencing of algebraic effects.
4. **Defer Metaprogramming Macros**: We will keep the S-Expression grammar static for now, as hashing and content-addressing depend on a stable, unambiguous AST structure.

## Consequences
- The codebase remains focused and lightweight, avoiding the complection of formal verification with runtime concurrency.
- Code readability and developer experience will be improved by adding sequencing primitives to our S-expressions.
