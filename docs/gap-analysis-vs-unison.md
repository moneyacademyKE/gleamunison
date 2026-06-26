# Gap Analysis: gleamunison vs Unison

A Rich Hickey-style analysis of where our architectural specification diverges
from the actual Unison language runtime, and what each divergence means.

---

## Gap 1: Types ARE part of the hash in Unison (we said they aren't)

**What Unison does:**
"A hash in Unison is a 512-bit SHA3 digest of **a term or a type's internal
structure**, excluding all names."

The type IS part of the term's identity. Not the type annotation, not the
source-level type signature — the *internal type* (the structural type after
inference). Two terms with the same AST but different types have DIFFERENT
hashes.

**What we did:**
ADR-0002: "No Type fields on any Term constructor. Types are computed after
hashing and stored in a separate TypeCache."

**Why Unison does it this way:**
The type determines how a term behaves at runtime in a language with
overloading or type-directed dispatch. In Unison, `x + 1` behaves differently
if x is a `Nat` vs an `Int` — the type IS semantically meaningful. Excluding
the type from the hash would mean two terms with the same structure but
different runtime behavior would have the same identity. That's wrong.

**The gap:**
Our ADR-0002 was motivated by a concern that type annotations shouldn't change
hashes. That's correct — *annotations* shouldn't. But the *inferred type*
should. We confused "type annotations are not identity" with "types are not
identity." Those are different things.

**Action:** Types must be part of the hash. Specifically:
- The *canonical, inferred type* of a definition goes into the hash
- Type annotations on the surface syntax don't (they elaborate to the inferred
  type before hashing)
- This means type inference runs BEFORE hashing, not after
- The pipeline becomes: Surface → Elaborate → **Infer types** → Hash → Codebase
- ADR-0002 must be updated: types ARE in the hash, but as inferred types, not
  annotated types

---

## Gap 2: Unison has builtin escape hatch `##` (we eliminated ours with genesis)

**What Unison does:**
Built-in references use `##` prefix: `##Nat`, `##Int`. This is a second
identity system — a parallel hash space for primitives.

**What we did:**
Pure genesis: ALL definitions, including primitives, are regular hash-based
definitions seeded from a genesis block. No second identity system.

**Analysis:**
Unison's `##` approach is pragmatically simpler — they don't need to author
AST definitions for `Int.add` in the language itself. But it creates exactly
the dual-identity problem we identified.

**Verdict:**
Our approach is BETTER here. Genesis builtins are the cleaner design.
Unison's `##` is a pragmatic shortcut for their bootstrapping problem.
The genesis approach eliminates the `##` complexity at the cost of a
bootstrapping tool.

**No action needed.** This is an area where we improved on Unison.

---

## Gap 3: Unison's ability model is fundamentally different

**What Unison does:**
- Abilities are declared with constructors-as-operations
- `handle e with h` passes a `Request A T` value to handler `h`
- The handler pattern-matches on the Request constructors
- The continuation `k` is an explicit pattern variable
- The handler uses recursive `handle k ... with handler` calls to maintain
  the handling context across continuation calls

The key type:
```
handle e with h
  where e : {A} T
        h : Request A T -> R
  result : R
```

**What we do:**
- Abilities are declared with positional operations
- `Do(ability, op, args)` looks up the handler on a dynamic scope stack
- The handler is a map of op_index -> function
- The continuation is an implicit closure, not an explicit pattern variable
- No recursive handler calls needed — the runtime maintains the context

**Analysis — this is the biggest divergence:**

Unison's model is:
- **Explicit continuation** — `k` is a variable the handler manipulates
- **Explicit handler recursion** — `handle k val with storeHandler` creates a
  new handling scope for each continuation
- **Ability operations as data** — `Store.get` is a data constructor that
  appears in patterns
- **Single handler function** — one function handles ALL operations of an
  ability by pattern matching

Our model is:
- **Implicit continuation** — the closure captures it, invisible to the user
- **Implicit handler context** — the dynamic scope stack persists it
- **Ability operations as indices** — positional, not named in patterns
- **Multiple handler functions** — one function per operation, in a map

Consequences of our model:
- **Simpler handler writing**: User provides `{readLine: fn(_, r) -> r("x")}`
  instead of a recursive pattern-matching function
- **Less flexible**: Users can't see or transform the continuation explicitly.
  Some patterns (like the recursive `storeHandler` above) are harder to
  express because the user doesn't control the recursion boundary
- **The `Request` type doesn't exist**: There's no type-level representation
  of "a computation requesting an ability." This simplifies the type system
  but loses information

**Is this a problem for a prototype?**
Not necessarily. Our model is a valid subset of Unison's model — we handle
the common cases. The question is: can we express Unison's recursive handler
pattern (like `storeHandler`) in our model? Let's check:

```gleam
// In our model, Store handler:
store_handler = {
  get: fn(_, resume) -> resume(current_value),    // but wait — how do we update current_value?
  put: fn(args, resume) -> 
    let new_value = args[0]
    resume(())  // and now the handler has a new current_value...
  ]
}
```

The problem: our handler is a static map of functions. The `storeHandler`
needs to maintain *mutable state* (the stored value) across calls. In
Unison's model, this is done via:
1. The handler function takes `storedValue` as a parameter
2. Each recursive call to `handle ... with storeHandler newValue` passes the
   updated value

In our model, the handler functions are closures. They CAN capture mutable
state (via the process dictionary or an ETS table). But this is less clean
than Unison's explicit parameter threading.

**Action:** Document this limitation. For the prototype, our model is simpler
to implement and covers the common cases (IO, abort, stream). If stateful
abilities like `Store` are needed, they can use process-dictionary state
behind the closure. A future version can add full `Request` pattern matching
as a more expressive (but more complex) alternative.

---

## Gap 4: No `Request A T` built-in type

**What Unison has:**
The `Request A T` type is a built-in type constructor that bridges abilities
and the type system. It represents "a computation of type T that requires
ability A." The `handle` expression creates `Request` values and passes them
to handlers.

**What we have:**
No `Request` type. The `Do` and `Handle` terms are compiled directly to
runtime calls with closures. There's no type-level representation of "a
computation pending an ability" — the type checker just tracks which abilities
are required via the `Requirement` type.

**Analysis:**
`Request` serves two purposes in Unison:
1. **Type-level**: captures that a computation needs an ability
2. **Runtime-level**: provides a value for the handler to pattern-match on

In our model:
1. **Type-level**: `Requirement` tracks abilities — same effect, different
   mechanism
2. **Runtime-level**: The closure captures the continuation — no value needed

The `Request` type would add complexity (a whole new type constructor and
type rules) without adding functionality we need for the prototype.

**No action needed for prototype.** The `Request` type is an implementation
detail of Unison's explicit-handler model, not a required feature of any
effect system. Our implicit-handler model achieves the same result with less
type machinery.

---

## Gap 5: Unison uses SQLite (event-sourced); we use in-memory Map

**What Unison does:**
The codebase is stored in SQLite. It's an append-only event log — every change
(including deletions) is appended. This enables:
- Time-travel debugging
- Rollback
- Crash recovery
- Concurrent access

**What we do:**
`Codebase` is an in-memory `Map(Ref, Definition)`. DETS was mentioned but not
specified. No event log, no versioning, no persistence.

**Analysis:**
SQLite is the right choice for Unison because the codebase IS the primary
storage — there are no source files. For us, the codebase is derived from
source files via elaboration + hashing. Different use case.

For a prototype, in-memory storage is fine. But for any real use, we need:
- Durability (DETS, SQLite, or file-based)
- Append-only event log (enables sync reconciliation)
- The `Codebase` type already separates `defs` from `meta` — adding an
  event log is a natural extension

**Action:** Update `codebase.gleam` to specify a pluggable storage backend
with SQLite as the production target. Document that the in-memory Map is
for prototyping only.

---

## Gap 6: Unison has structural vs unique types

**What Unison does:**
```
structural type Option a = None | Some a
unique type UserId = UserId Nat
```

- **Structural types**: identity = hash of the structure. Two identical
  declarations produce the same hash.
- **Unique types**: identity includes a GUID. Each declaration gets a unique
  hash even if structurally identical.

**What we do:**
Nothing. Our `TypeDeclaration` has no `structural` vs `unique` distinction.
All types are implicitly structural.

**Analysis:**
Unique types solve a practical problem: sometimes you want two types with the
same structure to be DIFFERENT (e.g., `Email` and `Url` are both `Text`, but
shouldn't be interchangeable). Without unique types, you need newtypes or
wrappers.

**Action:** Add `structural` vs `unique` to `TypeDeclaration`:
```gleam
pub type TypeDeclaration {
  Structural(name: LocalVar, parameters: List(LocalVar), constructors: List(Constructor))
  Unique(name: LocalVar, guid: String, parameters: List(LocalVar), constructors: List(Constructor))
}
```

The GUID in Unique types is part of the hash, so two structurally identical
`Unique` types with different GUIDs produce different hashes.

---

## Gap 7: Unison has full ability row polymorphism

**What Unison does:**
A function type `a ->{e} b` where `e` can be a type variable. This enables:
```haskell
map : (a ->{e} b) -> [a] ->{e} [b]
forkAll : [() ->{e} ()] ->{e} ()
```

The ability set `{e}` is polymorphic — it stands for "any set of abilities."
When `map` is called with a function requiring `{IO}`, `e` is instantiated
to `{IO}`.

**What we do:**
`Fn(params, result, requires: List(AbilityRef))` — the `requires` field is a
concrete list of abilities. No type variable for ability sets.

**Analysis:**
Ability polymorphism is essential for Higher-Order Functions (HOFs). Without
it, passing a function that uses abilities to `map` would fail type-checking
because `map`'s type says `requires: []`, and the argument requires `{IO}`.

The subtype rule we defined (fewer requirements is a subtype of more
requirements) helps: a pure function can be passed where `{IO}` is expected.
But it doesn't help in REVERSE: you can't pass an `{IO}` function where
`{}` is expected.

For HOFs, you need either:
1. **Ability polymorphism** (Unison's approach): `map : (a ->{e} b) -> [a] ->{e} [b]`
2. **Dynamic effect detection** (less safe): the runtime checks if effects
   happen and propagates them
3. **Manual threading**: the caller wraps the effectful function to handle
   abilities before passing it

**Action:** Add ability type variables to `Type`:
```gleam
pub type Type {
  ...
  /// Ability set variable — stands for "any set of abilities"
  AbilityVar(index: Int)
}

pub type Requirement {
  Required(abilities: List(Either(AbilityRef, Int)>))
  // Either concrete AbilityRef or type variable index
}
```

This enables `map : (a ->{e} b) -> List(a) ->{e} List(b)` by:
1. `map`'s parameter function has type `Fn([a], b, Required([Right(0)]))`
   where `0` is the ability variable index
2. `map`'s result has the same requirement
3. When `map` is applied to an `{IO}` function, variable `0` is unified
   with `AbilityRef(IO)` in both parameter and result

**Priority:** Medium for prototype. Without this, HOFs with effectful
arguments don't type-check. But for a prototype where most functions are
first-order, it's not blocking.

---

## Gap 8: Unison has projects, branches, namespaces

**What Unison does:**
The codebase has a full project/branch/namespace hierarchy:
```
myproject/main/lib/base/...
|          |    |   |
|          |    |   +-- base library
|          |    +-- dependencies
|          +-- branch (like git)
+-- project (like git repo)
```

Namespaces organize code. Projects manage versions. Branches enable parallel
development.

**What we have:**
`Namespace(entries: Map(String, DefinitionRef))` — a flat map of names to
refs. No hierarchy, no projects, no branches.

**Analysis:**
This is a full product feature, not an architectural primitive. Unison's
project system evolved over years. For our prototype, a flat namespace is
fine.

**No action needed.** This is scope. A hierarchical namespace can be layered
on top later.

---

## Gap 9: Unison has a distributed `Remote` ability

**What Unison does:**
Unison has a `Remote` ability for distributed computation:
```haskell
remoteCompute : Location -> (() ->{Remote} a) ->{IO, Remote} a
```

A `Location` represents a computing context with access to certain resources.
The `Remote` ability enables sending computations to other nodes and getting
results back.

**What we have:**
A `Sync` module for codebase synchronization (exchanging definitions between
nodes) but NO ability model for distributed computation. There's no `Remote`
ability, no `Location` type, no way to send a computation to another node.

**Analysis:**
This is a significant gap but far beyond prototype scope. Unison's distributed
computing model is built on top of their ability system and requires:
- Serializable continuations (the entire computation up to the next `Do`)
- Node-to-node communication primitives
- Location-aware types
- A remote execution runtime

Our prototype's Sync module handles codebase synchronization only — the
simpler part of distribution.

**No action needed.** Document as out-of-scope for the prototype.

---

## Gap 10: Unison requires top-level definitions to be pure

**What Unison does:**
Top-level definitions must be pure (no abilities in scope). To run an
effectful computation at the top level, you wrap it in a lambda:
```haskell
-- This doesn't typecheck:
msg = printLine "hello"

-- This does:
msg = '(printLine "hello")
```

The quote `'` delays the computation into a function body, where ability
requirements are inferred.

**What we have:**
No such constraint documented. Our type inference rules don't distinguish
between top-level and nested scope for ability checking.

**Analysis:**
This constraint exists in Unison because the codebase is evaluated at load
time. Running an effectful computation during codebase loading would be
surprising and dangerous. We need the same constraint.

**Action:** Add to the type checker: top-level definitions (roots in a
`Unit`) must have `requirement = empty`. Implemented as a simple check
after type inference:
```gleam
pub fn check_top_level(cache: TypeCache, ref: DefinitionRef) -> Result(Nil, InferenceError) {
  let typ = lookup_type(cache, ref)
  case typ {
    CTTerm(type: Fn(_, _, requires: Required([]))) -> Ok
    CTTerm(type: Fn(_, _, requires: _)) -> Error(UnhandledAbility(...))
    _ -> Ok  // type declarations and ability decls are always fine
  }
}
```

---

## Summary: Action items

| Gap | Severity | Status | Action |
|---|---|---|---|
| **Gap 1**: Types in hash | Critical | **COMPLETED** | `Definition.TermDef` now includes `typ: Type`. ADR-0002 amended by ADR-0009. Pipeline: Elaborate → Type Check → Hash. |
| **Gap 2**: `##` builtins | None | No action | Our genesis approach is better. Keep it. |
| **Gap 3**: Ability model | Watch | Documented | Our closure-passing model is simpler for common cases. Stateful-handler limitation documented in LEARNINGS.md. |
| **Gap 4**: `Request` type | None | No action | Not needed for our implicit-handler model |
| **Gap 5**: SQLite/event log | Low | **PARTIAL** | Added `StorageBackend` type with InMemory/DETS/SQLite variants. Prototype uses InMemory. |
| **Gap 6**: Structural vs unique | Low | **COMPLETED** | `TypeDeclaration` split into `Structural` and `Unique` variants with GUID field. |
| **Gap 7**: Row polymorphism | Medium | **COMPLETED** | Added `AbilityVar` to `Type`, `ReqElement` (Concrete/ReqVar) to `Requirement`. |
| **Gap 8**: Project/branch | None | No action | Out of scope for prototype |
| **Gap 9**: Remote ability | None | No action | Out of scope for prototype |
| **Gap 10**: Top-level purity | Low | **COMPLETED** | Added `check_top_level` to type checker. `ImpureTopLevel` error variant. |

**Remaining gaps (none blocking):**

All critical and medium gaps are closed. Remaining items are either:
- Conscious scope decisions (Gaps 2, 4, 8, 9)
- Simple additions that can be made during implementation (Gap 5 - choosing
  the SQLite backend when production readiness is needed)
- Ongoing monitoring (Gap 3 - our model handles common cases but may need
  extension for complex stateful handlers)

**Detailed ability system analysis:** See `docs/gap-analysis-ability-system.md`
for a deep dive on Gap 3, including five specific drawbacks identified and
their mitigations (typed handler validation, named→positional elaboration,
StatefulHandler pattern).
