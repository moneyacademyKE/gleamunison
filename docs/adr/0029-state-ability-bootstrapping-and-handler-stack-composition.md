# 29. State Ability Bootstrapping and Handler Stack Composition

## Status
Accepted

## Context
Level 35 tests the dynamic dispatch and composition of a `State` ability. The parser does not support parsing ability declarations like `define-ability` in the surface language.

## Decision
We bootstrapped the `State` ability in the REPL's environment initialization using `SurfaceAbilityDef` with `get` and `set` operations. To handle State effects, we defined a `StateHandler` mapping to the State's hashed module key (`fe60582e`) and composed it with `ConsoleHandler` in the Erlang FFI:
```erlang
gleamunison_effets:handle_comp(ConsoleHandler, fun() ->
    gleamunison_effets:handle_comp(StateHandler, fun() ->
        ModuleAtom:'$eval'()
    end)
end)
```

## Consequences
- Allows successful elaboration and verification of `State` and `Console` compositions.
- State operations successfully retrieve and update values in the process dictionary.
