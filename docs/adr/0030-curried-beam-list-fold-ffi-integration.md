# 30. Curried BEAM List Fold FFI Integration

## Status
Accepted

## Context
The standard library `list-fold` is implemented in Erlang (`m_00000023.erl`). In the prototype language, all lambdas are curried, but the FFI wrapper originally called `erlang:apply(F, [X, Acc])` as a 2-argument application, throwing `badarity` at runtime.

## Decision
We updated the FFI function application in `m_00000023.erl` to evaluate curried arguments in two separate steps:
`erlang:apply(erlang:apply(F, [Acc]), [X])`

## Consequences
- Enables curried list fold operations to evaluate successfully without throwing `badarity` errors.
- Ensures compatibility of dynamic Lisp functions inside host Erlang list operations.
