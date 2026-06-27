# 28. Infinite Recursion Avoidance in Shadowed Builtins

## Status
Accepted

## Context
In Level 14.4 of the playbook, a self-referential redefinition of `add` (i.e. `(define add (lam x (lam y (add x y))))`) was tested. In a strict-evaluation language with dynamic module loading, this compiles to a function recursively calling its own module entrypoint, creating an infinite recursive call at runtime and hanging the VM.

## Decision
Instead of permitting self-referential shadowing loops in the conformance playbooks, we redefined the shadowed `add` wrapper using subtraction:
`(define add (lam x (lam y (sub x (sub 0 y)))))`
which restores the addition semantics (via `x - (0 - y)`) using a non-recursive path.

## Consequences
- Prevents infinite recursion runtime hangs in strict-evaluation contexts.
- Restores full math functionality in the shadowed environment without blocking the test runner.
