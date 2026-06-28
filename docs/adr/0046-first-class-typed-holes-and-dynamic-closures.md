# ADR 0046: First-Class Typed Holes and Dynamic Closures

## Context
1. **Developer Velocity in Incomplete Code**: Traditional functional runtimes fail compilation when type conflicts or missing definitions occur.
2. **Hazel's Total Liveness**: Hazel treats incomplete code as a first-class citizen using "membranes" around holes. Hitting a hole allows evaluation to proceed around it and return a hole closure containing the local variables.
3. **Resumable BEAM Closures**: Since `gleamunison` supports serializable continuations, hitting a hole at runtime could suspend the Erlang process, capture its continuation, and wait for the hole to be dynamically filled via the REPL/dashboard before resuming execution.

## Decision
1. **Represent Holes in AST**: Add `ast.Hole(name: String, inputs: List(Term))` to the Core AST.
2. **Compiler Exception / Effect**: Compile `Hole` nodes to a runtime throw or an algebraic effect request. Hitting a hole interrupts evaluation, serializes the local scope, and yields control back to the debugger/REPL.
3. **Gradual Typechecking**: Modify the typechecker to unify holes with any type, allowing incomplete programs to pass type checking.

## Consequences
* Enables a completely live programming experience where incomplete and partially incorrect programs can be run and debugged interactively.
* Seamless integration with our existing dynamic module loading and serialization mechanisms.
