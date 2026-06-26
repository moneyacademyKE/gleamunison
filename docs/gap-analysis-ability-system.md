# Gap Analysis: Ability System vs Unison

Analysis of our closure-passing / dynamic-scope-stack ability model vs
Unison's Request-pattern-matching model, with concrete mitigations for
each identified drawback.

---

## Baseline: Two models compared

### Unison's model

```
handle e with h
  where e : {A} T         -- computation requiring ability A, returning T
        h : Request A T -> R  -- handler accepts Request, returns R
  result : R

-- Handler implementation (stateful example):
storeHandler storedValue = cases
  { Store.get -> k }    -> handle k storedValue with storeHandler storedValue
  { Store.put v -> k }  -> handle k () with storeHandler v
  { x }                 -> x    -- pure case: no more requests
```

**Key properties:**
- `Request A T` is a BUILT-IN TYPE CONSTRUCTOR — the ability requirement is
  part of the type system
- The continuation `k` is EXPLICIT — a named pattern variable with a known type
- The handler is RECURSIVE — it calls `handle ... with handler` explicitly
  for each continuation, which establishes a new handling scope
- Handler EXHAUSTIVENESS is checked — `{ x }` covers the pure case, all
  operation constructors must be matched
- Operations are NAMED constructors — `Store.get`, `Store.put`
- State flows through FUNCTION PARAMETERS — `storeHandler storedValue`

### Our model

```
Handle(computation, handler)
  -- handler evaluates to a map #{ops => {op_idx => fn(args, resume) -> result}}
  -- computation is evaluated with the handler on the dynamic scope stack

-- Handler implementation (stateful example):
handler = {
  0: fn([], resume) -> resume(current_value),     -- Store.get
  1: fn([v], resume) -> resume(()),                -- Store.put
}
-- State lives in ETS or process dictionary, not in handler params
```

**Key properties:**
- No `Request` type — `Requirement` is a type-checker-internal concept
- The continuation `resume` is an IMPLICIT CLOSURE — a function argument
- The handler is STATIC — a map of closures, no recursion needed
- No exhaustiveness checking — missing operations crash at runtime
- Operations are POSITIONAL — indexed by de Bruijn position
- State lives in SIDE CHANNELS — ETS, process dict, gen_server

---

## Drawback A: No type safety at the handler boundary

**What we have:**
```gleam
pub type OpHandler =
  fn(List(Dynamic), fn(Dynamic) -> Dynamic) -> Dynamic
```

Everything is `Dynamic`. The type checker cannot verify:
- The handler function receives the right number/type of arguments for the
  operation's declared inputs
- The continuation receives the right type matching the operation's output
- The handler returns the correct result type for the enclosing context

**What Unison has:**
The handler's type is `Request A T -> R`, where:
- `A` is the ability being handled
- `T` is the computation's return type
- Each operation pattern has types derived from the ability declaration:
  `{Store.get -> k}` where `k : v -> {Store v} a`

**Consequence:** In our model, handler errors are runtime crashes. In Unison,
they're compile-time type errors.

### Mitigation A: Typed handler validation

Add a compile-time validation pass that checks handler maps against ability
declarations. The elaborator/typechecker:

1. When it sees `Handle(computation, handler_term)`, it evaluates the handler
   term's structure (if it's a map literal at compile time)
2. It looks up the ability declaration from the handler's ability ref
3. For each operation in the ability, it checks that the handler map has a
   corresponding entry
4. It checks that the handler's arity matches the operation's input types
5. It emits a compile-time error for missing or mismatched operations

This is NOT full type safety (the handler is still `Dynamic` at runtime) but
it catches the most common errors at compile time: missing operations, wrong
number of arguments, and type mismatches in simple cases.

```gleam
pub fn validate_handler(
  cache: TypeCache,
  ability_ref: DefinitionRef,
  handler_ops: Map(Int, Term),
) -> Result(Nil, HandlerError) {
  // Look up the ability declaration
  // For each operation: check presence, check arity, check input types
  todo
}

pub type HandlerError {
  MissingOperation(ability: DefinitionRef, op_index: Int, op_name: String)
  ExtraOperation(ability: DefinitionRef, op_index: Int)
  ArityMismatch(ability: DefinitionRef, op_index: Int, expected: Int, got: Int)
  TypeMismatch(ability: DefinitionRef, op_index: Int, message: String)
}
```

**Where to add:** New function in `types.gleam` or a new module
`ability_check.gleam`. Called from `elaborate.typecheck_unit`.

**Priority:** High. This is the most impactful fix for the least complexity.

---

## Drawback B: Stateful handlers require side channels

**What we have:**
A static map of closures. State must be stored externally:

```gleam
// State lives in ETS — invisible to the type system
store_handler = {
  0: fn([], resume) ->
    state = read_state_from_ets()
    resume(state)
  1: fn([v], resume) ->
    write_state_to_ets(v)
    resume(())
}
```

**What Unison has:**
State is a function parameter threaded through recursive handler calls:

```haskell
storeHandler storedValue = cases
  {Store.get -> k}   -> handle k storedValue with storeHandler storedValue
  {Store.put v -> k} -> handle k () with storeHandler v
  {x} -> x
```

Each recursive `handle` call creates a new scope with the updated state.
No side channels needed.

**Consequence:** Our model requires mutable state for anything more complex
than stateless IO. The state management is ad-hoc and untracked.

### Mitigation B: Handler state pattern

Document the pattern for stateful handlers using Erlang's `persistent_term` or
a gen_server, but ALSO add a higher-level abstraction:

```gleam
/// A stateful handler builder. Takes an initial state and a function
/// that updates state on each operation.
/// This compiles to: gen_server with state, operations as messages.
pub type StatefulHandler(state, req, res) {
  StatefulHandler(
    initial: state,
    operations: Map(Int, fn(state, List(Dynamic), fn(Dynamic) -> Dynamic) -> #(state, Dynamic)),
  )
}
```

This transforms the ad-hoc side channel into a structured pattern:
- The builder manages the state lifecycle
- Each operation receives the current state and returns an updated state
- The runtime creates a gen_server behind the scenes

For the prototype, document the ETS pattern as sufficient but note the
gen_server abstraction as a future improvement.

**Where to add:** New type in `effects.gleam`, documented pattern in
`docs/PATTERNS.md`.

**Priority:** Low for prototype. Most abilities (IO, Abort, Clock, Random)
are stateless. Stateful abilities like Store are edge cases.

---

## Drawback C: Positional operation indices are fragile

**What we have:**
```gleam
Do(ability: DefinitionRef, operation: LocalVar(0), args: List(Term))
```

Operation `0` means "the first operation in the ability declaration."
If the ability declaration changes, all indices shift — existing handlers
call wrong operations silently.

**What Unison has:**
```haskell
structural ability Store v where
  get : v
  put : v -> ()
```

Operations are named constructors: `Store.get`, `Store.put`. The name is
resolved at compile time to a constructor reference. Adding a new operation
doesn't shift existing ones.

**Consequence:** Our positional scheme makes ability evolution error-prone.
Adding an operation to an existing ability silently breaks all downstream
handlers.

### Mitigation C: Named elaboration to indices

Surface syntax uses names; the core AST uses indices. The elaborator maps
names to positions at compile time and emits a compile-time error if a name
is unresolved:

```gleam
// Surface syntax (user writes):
// ability Store v { get : v; put : v -> () }
// handle ... with Store = { get = fn(_, resume) -> resume(v); ... }

// Elaboration:
// 1. Resolve "get" → position 0 in the Store ability declaration
// 2. Produce core AST with positional indices
// 3. If "get" not found in Store → compile error
```

This means:
- Adding an operation in the middle still shifts indices (because the hash
  changes — it's a different ability)
- But the elaborator catches the mismatch at compile time rather than runtime
- The user never sees indices — they use names in source code

```gleam
pub type ElaborateError {
  UnknownOperation(ability: String, operation: String)
  // ...
}
```

**Where to add:** Already partially in `elaborate.gleam` (`SurfaceOperation`,
`elaborate_ability`). The validation needs to be added to
`elaborate_handle`.

**Priority:** High. This prevents a whole class of silent runtime bugs.

---

## Drawback D: No handler exhaustiveness checking

**What we have:**
```gleam
handler = { 0: fn(_, resume) -> resume(42) }  // Only handles op 0
```

If the ability has 3 operations, this handler only covers 1. Missing
operations crash at runtime with `{unhandled_ability, Ref}`.

**What Unison has:**
The `{ x }` pattern is the exhaustiveness catch-all. The compiler warns
about unmatched constructors, just like any pattern match on a data type.

**Consequence:** Silent bugs. A handler that forgets an operation compiles
fine and crashes at runtime.

### Mitigation D: Exhaustiveness validation

Same as Mitigation A — the `validate_handler` function checks that every
operation in the ability declaration has a corresponding entry in the
handler map. Combined with Mitigation C (named elaboration), this gives
compile-time safety for handler completeness.

```gleam
pub fn validate_handler(...) -> Result(Nil, HandlerError) {
  // For each operation in the ability:
  //   - Check that handler_ops has an entry for this index
  //   - If not: MissingOperation error
  // Check that handler_ops has no entries beyond the ability's operations
  //   - If so: ExtraOperation error
}
```

**Where to add:** Same function as Mitigation A.

**Priority:** High. Combined with Mitigation A, this is one function that
provides both type safety and exhaustiveness.

---

## Drawback E: No `Request` type in the type system

**What we have:**
`Requirement` tracks which abilities a term needs, but it's a
type-checker-internal concept. There's no type-level value that represents
"a computation that HAS requested ability A and is waiting for a response."

**What Unison has:**
`Request A T` is a built-in type. It appears in:
- Handler signatures: `h : Request A T -> R`
- The type of `handle e with h`: if `e : {A} T` and `h : Request A T -> R`,
  then `handle e with h : R`

**Consequence:** We can't pass pending computations as values, can't compose
handlers generically, and can't write functions that operate on requests.

### Mitigation E: Document as intentional simplification

For the prototype, this is correct scope management. The `Request` type
enables:
- Composing handlers (e.g., sequencing two ability handlers)
- Writing generic handler combinators
- Passing a pending computation to another function

None of these are needed for the prototype's target use cases (IO, Abort,
Clock, Random). The `Request` type can be added later as a built-in type
without changing the runtime model.

**Where to add:** Document in `docs/LEARNINGS.md` as a known simplification.
Reference in `docs/gap-analysis-vs-unison.md` (Gap 4).

**Priority:** None for prototype. Nice-to-have for future.

---

## Implementation plan

| Mitigation | What to change | Complexity | Priority |
|---|---|---|---|
| **A: Typed handler validation** | Add `validate_handler` to `types.gleam`, add `HandlerError` type | Medium | **High** |
| **C: Named elaboration to indices** | Add name→index resolution in `elaborate.gleam`, catch unknown operations at compile time | Low | **High** |
| **D: Exhaustiveness checking** | Same function as A — validates all operations are covered | Low | **High** |
| **B: Stateful handler pattern** | Add `StatefulHandler` type to `effects.gleam`, document pattern | Medium | Low |
| **E: `Request` type** | Defer. Document as intentional. | High | None |

**Total for High priority:** Add one new function (`validate_handler`) and
amend one existing function (`elaborate_handle` to resolve names). ~50 lines
of Gleam spec.
