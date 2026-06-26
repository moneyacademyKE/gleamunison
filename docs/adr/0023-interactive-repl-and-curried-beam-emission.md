# ADR 0023: Interactive REPL and Curried BEAM Emission

## Context
1. **Interactive Evaluation**: Dogfooding requires executing arbitrary user S-expressions dynamically.
2. **Curried Call Syntax Errors**: Directly compiling curried applications as `(F(X))(Y)` violates Erlang syntax rules, causing VM compile-time parse errors.
3. **Storage vs. VM Linkage**: Codebase insertion requires structural hashing, but references between compiled definitions in the VM rely on name-based modules.

## Decision
1. **Dynamic REPL loop**: Implement a pure state-threading loop that consumes stdin, elaborates S-expressions, updates codebase/cache, and loads modules into the VM.
2. **Dynamic Dispatch**: Compile curried applications using recursive `erlang:apply/2` calls (e.g. `erlang:apply(erlang:apply(F, [X]), [Y])`).
3. **Split Loading/Storage**: Insert definitions in the codebase under their structural hash to pass verification, but load them in the VM under name-based module keys to resolve AST references.
4. **Bootstrapped Ambient Handlers**: Wrap execution in a default Console handler mapping prints to stdout.

## Consequences
- Warning-free, zero-dependency REPL runs on any standard Erlang VM.
- Curried functional programs compile to syntactically correct Erlang.
- Structural codebase purity is preserved while maintaining VM linking.
